// Single radix trie — nodes carry typed edges; no separate compiled-route list.
// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'path.dart';

// ── node ──────────────────────────────────────────────────────────────────────

class _Node<T> {
  final Map<String, _Node<T>> statics = {};
  List<_Edge<T>>? edges; // sorted by priority: high-pattern → param → low-pattern → catch-all → deferred
  MethodSlot<T>? slot; // routes terminating exactly here
}

// ── edges ─────────────────────────────────────────────────────────────────────

sealed class _Edge<T> {}

/// `:name` — matches one segment, recurses into child.
class _ParamEdge<T> extends _Edge<T> {
  final _Node<T> child = _Node<T>();
}

/// `**` — matches all remaining segments.
class _CatchAllEdge<T> extends _Edge<T> {
  final MethodSlot<T> slot;
  _CatchAllEdge(this.slot);
}

/// Compiled regex — handles every other complex syntax.
class _PatternEdge<T> extends _Edge<T> {
  final RegExp regex;
  final String shape; // full-path shape for duplicate detection
  final int bucket; // bucketHigh / bucketLate / bucketRepeat / bucketDeferred
  final List<int> groupIndexes;
  MethodSlot<T> slot;
  _PatternEdge(this.regex, this.shape, this.bucket, this.groupIndexes, this.slot);
}

// ── edge priority ─────────────────────────────────────────────────────────────

int _edgePri(_Edge<dynamic> e) => switch (e) {
  _PatternEdge<dynamic>(bucket: final b) when b == bucketHigh => 0,
  _ParamEdge<dynamic>() => 1,
  _PatternEdge<dynamic>(bucket: final b) when b != bucketDeferred => 2,
  _CatchAllEdge<dynamic>() => 3,
  _ => 4, // bucketDeferred
};

// ── radix engine ──────────────────────────────────────────────────────────────

class Radix<T> {
  Radix(this.caseSensitive);

  final bool caseSensitive;
  final _exact = <String, MethodSlot<T>>{};
  final _root = _Node<T>();

  bool _hasNonExact = false;
  bool _hasPatterns = false;
  bool _hasWildcards = false;

  bool get hasNonExact => _hasNonExact;
  bool get needsStrict => _hasWildcards || _hasPatterns;

  // ── registration ──────────────────────────────────────────────────────────

  void add(
    String path,
    T data,
    String? method,
    DuplicatePolicy policy,
    int order,
  ) {
    if (!path.startsWith('/')) {
      throw FormatException('Route pattern must start with "/": $path');
    }
    final norm = trimTrailingSlash(path);

    // Quick scan: any special chars?
    var hasToken = false;
    for (var i = 1; i < norm.length; i++) {
      final c = norm.codeUnitAt(i);
      if (c == colonCode ||
          c == asteriskCode ||
          c == openBraceCode ||
          c == closeBraceCode ||
          c == questionCode) {
        hasToken = true;
        break;
      }
    }
    if (!hasToken) {
      _addExact(norm, data, method, policy, order);
      return;
    }

    var node = _root;
    final names = <String>[];
    var staticChars = 0, depth = 0;
    var cursor = norm.length == 1 ? norm.length : 1;

    while (cursor < norm.length) {
      final segEnd = findSegmentEnd(norm, cursor);
      if (segEnd == cursor) throw FormatException('$emptySegment$norm');
      final firstCode = norm.codeUnitAt(cursor);
      final segComplex = _segmentHasComplex(norm, cursor, segEnd);

      // ** catch-all
      if (firstCode == asteriskCode) {
        final restName = readRestName(norm, cursor, segEnd);
        if (restName != null) {
          if (segEnd != norm.length) {
            throw FormatException(
              'Double wildcard must be the last segment: $norm',
            );
          }
          _validateCaptureNames(names, restName, norm);
          final entry = RouteEntry<T>(
            data,
            names,
            restName,
            specRem,
            depth,
            staticChars,
            0,
            order,
          );
          _hasWildcards = true;
          _hasNonExact = true;
          final dupPrefix =
              cursor == 1 && names.isEmpty ? dupFallback : dupWildcard;
          // Find or create _CatchAllEdge
          _CatchAllEdge<T>? cae;
          for (final e in node.edges ?? []) {
            if (e is _CatchAllEdge<T>) {
              cae = e;
              break;
            }
          }
          if (cae == null) {
            cae = _CatchAllEdge(MethodSlot<T>());
            _insertEdge(node, cae);
          }
          cae.slot.add(method, entry, policy, norm, dupPrefix);
          return;
        }
        // Single * → complex: fall through to pattern compilation
      }

      // Simple :name param
      if (firstCode == colonCode && !segComplex) {
        if (!validParamSlice(norm, cursor + 1, segEnd)) break;
        _ParamEdge<T>? pe;
        for (final e in node.edges ?? []) {
          if (e is _ParamEdge<T>) {
            pe = e;
            break;
          }
        }
        if (pe == null) {
          pe = _ParamEdge<T>();
          _insertEdge(node, pe);
        }
        node = pe.child;
        names.add(norm.substring(cursor + 1, segEnd));
        depth++;
        cursor = segEnd < norm.length ? segEnd + 1 : norm.length;
        continue;
      }

      // Complex segment (embedded *, :name?, :name+, {…}, or bare :name with bad chars)
      if (segComplex || firstCode == colonCode || firstCode == asteriskCode) break;

      // Static segment
      final key =
          caseSensitive
              ? norm.substring(cursor, segEnd)
              : norm.substring(cursor, segEnd).toLowerCase();
      staticChars += segEnd - cursor;
      node = node.statics.putIfAbsent(key, _Node.new);
      depth++;
      cursor = segEnd < norm.length ? segEnd + 1 : norm.length;
    }

    if (cursor >= norm.length) {
      // Route terminates at this node
      _validateCaptureNames(names, null, norm);
      final entry = RouteEntry<T>(
        data,
        names,
        null,
        names.isEmpty ? specExact : specDyn,
        depth,
        staticChars,
        0,
        order,
      );
      node.slot ??= MethodSlot<T>();
      node.slot!.add(method, entry, policy, norm, dupShape);
      _hasNonExact = _hasNonExact || names.isNotEmpty;
    } else {
      // Complex segment: compile full-path regex, attach as _PatternEdge at current node
      _hasPatterns = true;
      _hasNonExact = true;
      final compiled = _PatternCompiler<T>(
        norm,
        data,
        caseSensitive,
        order,
      ).compile();
      if (compiled == null) {
        throw FormatException('Unsupported segment syntax in route: $norm');
      }
      // Merge into existing edge with same shape, or insert new one
      for (final e in node.edges ?? []) {
        if (e is _PatternEdge<T> && e.shape == compiled.shape) {
          e.slot.add(method, compiled.entry, policy, norm, dupShape);
          return;
        }
      }
      _insertEdge(
        node,
        _PatternEdge(
          compiled.regex,
          compiled.shape,
          compiled.bucket,
          compiled.groupIndexes,
          MethodSlot<T>()..add(method, compiled.entry, policy, norm, dupShape),
        ),
      );
    }
  }

  void _addExact(
    String path,
    T data,
    String? method,
    DuplicatePolicy policy,
    int order,
  ) {
    final depth = countSegments(path);
    final chars = countStaticChars(path) - 1;
    final entry = RouteEntry<T>(
      data,
      const [],
      null,
      specExact,
      depth,
      chars,
      0,
      order,
    );
    final key = caseSensitive ? path : path.toLowerCase();
    (_exact[key] ??= MethodSlot<T>()).add(method, entry, policy, path, dupShape);
  }

  /// Inserts [edge] into [node.edges] maintaining priority order.
  /// Within the same priority, [_PatternEdge]s are ordered by rank descending.
  void _insertEdge(_Node<T> node, _Edge<T> edge) {
    final es = node.edges ??= [];
    final p = _edgePri(edge);
    for (var i = 0; i < es.length; i++) {
      final ep = _edgePri(es[i]);
      if (ep > p) {
        es.insert(i, edge);
        return;
      }
      if (ep == p && edge is _PatternEdge<T> && es[i] is _PatternEdge<T>) {
        final cur = es[i] as _PatternEdge<T>;
        final ne = (edge).slot.any, ce = cur.slot.any;
        if (ne != null &&
            ce != null &&
            (ne.rank > ce.rank ||
                (ne.rank == ce.rank && ne.order < ce.order))) {
          es.insert(i, edge);
          return;
        }
      }
    }
    es.add(edge);
  }

  // ── single best match ─────────────────────────────────────────────────────

  RouteMatch<T>? match(String path, String? method) {
    final exactSlot = _exact[caseSensitive ? path : path.toLowerCase()];
    if (exactSlot != null) {
      final e = exactSlot.lookup(method);
      if (e != null) return e.plainMatch;
    }
    if (!_hasNonExact) return null;
    return _walk(_root, path, method, 1, []);
  }

  RouteMatch<T>? _walk(
    _Node<T> node,
    String path,
    String? method,
    int cursor,
    List<String> captures,
  ) {
    if (cursor >= path.length) {
      final e = node.slot?.lookup(method);
      if (e != null) return e.materialize(captures);
      // Catch-all with empty remainder, and deferred patterns
      for (final edge in node.edges ?? []) {
        if (edge is _CatchAllEdge<T>) {
          final entry = edge.slot.lookup(method);
          if (entry != null) return entry.materialize(captures, remainder: '');
        } else if (edge is _PatternEdge<T>) {
          final m = edge.regex.firstMatch(path);
          if (m == null) continue;
          final entry = edge.slot.lookup(method);
          if (entry != null) return _materializePattern(entry, edge.groupIndexes, m);
        }
      }
      return null;
    }

    final segEnd = findSegmentEnd(path, cursor);
    if (segEnd == cursor) return null;
    final next = segEnd < path.length ? segEnd + 1 : path.length;
    final seg =
        caseSensitive
            ? path.substring(cursor, segEnd)
            : path.substring(cursor, segEnd).toLowerCase();

    // Static child (always highest priority)
    final staticChild = node.statics[seg];
    if (staticChild != null) {
      final m = _walk(staticChild, path, method, next, captures);
      if (m != null) return m;
    }

    // Edges in priority order: high-patterns → param → low-patterns → catch-all
    // Deferred patterns are skipped here and retried after catch-all.
    for (final edge in node.edges ?? []) {
      if (edge is _PatternEdge<T>) {
        if (edge.bucket == bucketDeferred) continue;
        final m = edge.regex.firstMatch(path);
        if (m == null) continue;
        final entry = edge.slot.lookup(method);
        if (entry != null) return _materializePattern(entry, edge.groupIndexes, m);
      } else if (edge is _ParamEdge<T>) {
        final m = _walk(
          edge.child,
          path,
          method,
          next,
          [...captures, path.substring(cursor, segEnd)],
        );
        if (m != null) return m;
      } else if (edge is _CatchAllEdge<T>) {
        final entry = edge.slot.lookup(method);
        if (entry != null) {
          return entry.materialize(captures, remainder: path.substring(cursor));
        }
      }
    }

    // Deferred patterns last (optional — lowest priority)
    for (final edge in node.edges ?? []) {
      if (edge is! _PatternEdge<T> || edge.bucket != bucketDeferred) continue;
      final m = edge.regex.firstMatch(path);
      if (m == null) continue;
      final entry = edge.slot.lookup(method);
      if (entry != null) return _materializePattern(entry, edge.groupIndexes, m);
    }

    return null;
  }

  // ── collect all matches ───────────────────────────────────────────────────

  List<RouteMatch<T>> matchAll(String path, String? method) {
    final acc = MatchAccumulator<T>();
    final exactSlot = _exact[caseSensitive ? path : path.toLowerCase()];
    if (exactSlot != null) {
      exactSlot.collect(method, (entry, mr) {
        RouteEntry<T>? e = entry;
        while (e != null) {
          acc.add(e.plainMatch, e.rank, mr, e.order);
          e = e.next;
        }
      });
    }
    if (_hasNonExact) _walkCollect(_root, path, method, 1, [], acc);
    return acc.results;
  }

  void _walkCollect(
    _Node<T> node,
    String path,
    String? method,
    int cursor,
    List<String> captures,
    MatchAccumulator<T> acc,
  ) {
    // Collect edges at this node (catch-all and pattern edges)
    for (final edge in node.edges ?? []) {
      if (edge is _CatchAllEdge<T>) {
        final remainder = cursor >= path.length ? '' : path.substring(cursor);
        edge.slot.collect(method, (entry, mr) {
          RouteEntry<T>? e = entry;
          while (e != null) {
            acc.add(
              e.materialize(captures, remainder: remainder),
              e.rank,
              mr,
              e.order,
            );
            e = e.next;
          }
        });
      } else if (edge is _PatternEdge<T>) {
        final m = edge.regex.firstMatch(path);
        if (m == null) continue;
        edge.slot.collect(method, (entry, mr) {
          RouteEntry<T>? e = entry;
          while (e != null) {
            acc.add(
              _materializePattern(e, edge.groupIndexes, m),
              e.rank,
              mr,
              e.order,
            );
            e = e.next;
          }
        });
      }
    }

    if (cursor >= path.length) {
      node.slot?.collect(method, (entry, mr) {
        RouteEntry<T>? e = entry;
        while (e != null) {
          acc.add(e.materialize(captures), e.rank, mr, e.order);
          e = e.next;
        }
      });
      return;
    }

    final segEnd = findSegmentEnd(path, cursor);
    if (segEnd == cursor) return;
    final next = segEnd < path.length ? segEnd + 1 : path.length;
    final seg =
        caseSensitive
            ? path.substring(cursor, segEnd)
            : path.substring(cursor, segEnd).toLowerCase();

    final staticChild = node.statics[seg];
    if (staticChild != null) {
      _walkCollect(staticChild, path, method, next, captures, acc);
    }
    for (final edge in node.edges ?? []) {
      if (edge is! _ParamEdge<T>) continue;
      _walkCollect(
        edge.child,
        path,
        method,
        next,
        [...captures, path.substring(cursor, segEnd)],
        acc,
      );
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static RouteMatch<T> _materializePattern<T>(
    RouteEntry<T> entry,
    List<int> groupIndexes,
    RegExpMatch m,
  ) {
    if (entry.names.isEmpty) return entry.plainMatch;
    final params = <String, String>{};
    for (var i = 0; i < entry.names.length; i++) {
      final gi = groupIndexes[i];
      if (gi < 0) continue;
      final val = m.group(gi);
      if (val != null) params[entry.names[i]] = val;
    }
    return RouteMatch(entry.data, params);
  }

  bool _segmentHasComplex(String path, int start, int end) {
    for (var i = start; i < end; i++) {
      final c = path.codeUnitAt(i);
      if (c == asteriskCode ||
          c == openBraceCode ||
          c == closeBraceCode ||
          c == questionCode) {
        return true;
      }
    }
    return false;
  }

  void _validateCaptureNames(
    List<String> names,
    String? catchAll,
    String path,
  ) {
    final seen = <String>{};
    for (final n in names) {
      if (!seen.add(n)) {
        throw FormatException('Duplicate capture name in route: $path');
      }
    }
    if (catchAll != null && catchAll != '_') {
      if (!seen.add(catchAll)) {
        throw FormatException('Duplicate capture name in route: $path');
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Pattern compiler
// ══════════════════════════════════════════════════════════════════════════════

class _Compiled<T> {
  final RegExp regex;
  final String shape;
  final int bucket;
  final List<int> groupIndexes;
  final RouteEntry<T> entry;
  _Compiled(this.regex, this.shape, this.bucket, this.groupIndexes, this.entry);
}

class _PatternCompiler<T> {
  _PatternCompiler(this.pattern, this.data, this.caseSensitive, this.order);

  final String pattern;
  final T data;
  final bool caseSensitive;
  final int order;

  final regex = StringBuffer('^'), shape = StringBuffer('^');
  final names = <String>[], groupIndexes = <int>[];
  var groupCount = 0, unnamedCount = 0, staticChars = 0;
  var needsCompiled = false;
  var bucket = bucketHigh;
  var specificity = specDyn;
  var constraintScore = 0;

  _Compiled<T>? compile() {
    if (_containsStructuredBrace(pattern)) {
      needsCompiled = true;
      specificity = specStruct;
      if (constraintScore < 1) constraintScore = 1;
      writeGrouped(0, pattern.length, false, regex, shape);
      regex.write(r'$');
      shape.write(r'$');
      return _build();
    }
    for (
      var cursor = pattern.length == 1 ? pattern.length : 1;
      cursor < pattern.length;
    ) {
      final segEnd = findSegmentEnd(pattern, cursor);
      final first = pattern.codeUnitAt(cursor);
      if (segEnd == cursor) throw FormatException('$emptySegment$pattern');

      if (first == colonCode && validParamSlice(pattern, cursor + 1, segEnd)) {
        _writeCapture(
          regex,
          shape,
          '([^/]+)',
          pattern.substring(cursor + 1, segEnd),
          slashPrefixed: true,
        );
        cursor = segEnd + 1;
        continue;
      }
      if (segEnd - cursor == 1 && first == asteriskCode) {
        _writeCapture(
          regex,
          shape,
          '([^/]+)',
          '${unnamedCount++}',
          slashPrefixed: true,
        );
        needsCompiled = true;
        bucket = bucketLate;
        constraintScore = 1;
        cursor = segEnd + 1;
        continue;
      }
      if (first == colonCode) {
        final q = pattern.codeUnitAt(segEnd - 1);
        if (q == questionCode || q == plusCode || q == asteriskCode) {
          final name = pattern.substring(cursor + 1, segEnd - 1);
          if (!validParamSlice(name, 0, name.length)) {
            throw FormatException('Invalid parameter name in route: $pattern');
          }
          final capture = q == questionCode
              ? '([^/]+)'
              : q == plusCode
              ? '(.+(?:/.+)*)'
              : '(.*)';
          _writeCapture(
            regex,
            shape,
            capture,
            name,
            slashPrefixed: true,
            optional: q != plusCode,
          );
          needsCompiled = true;
          bucket = q == questionCode ? bucketDeferred : bucketRepeat;
          specificity = q == questionCode ? specStruct : specRem;
          constraintScore = 1;
          cursor = segEnd + 1;
          continue;
        }
      }
      regex.write('/');
      shape.write('/');
      _writeSegment(cursor, segEnd);
      cursor = segEnd + 1;
    }
    regex.write(r'$');
    shape.write(r'$');
    if (!needsCompiled) return null;
    return _build();
  }

  _Compiled<T> _build() => _Compiled(
    RegExp(regex.toString(), caseSensitive: caseSensitive),
    shape.toString(),
    bucket,
    groupIndexes,
    RouteEntry<T>(
      data,
      names,
      null,
      specificity,
      countSegments(pattern),
      staticChars,
      constraintScore,
      order,
    ),
  );

  void _writeCapture(
    StringBuffer outR,
    StringBuffer outS,
    String cap,
    String name, {
    int extraGroups = 0,
    bool slashPrefixed = false,
    bool optional = false,
  }) {
    if (optional) {
      outR
        ..write('(?:')
        ..write(slashPrefixed ? '/' : '')
        ..write(cap)
        ..write(')?');
      outS
        ..write('(?:')
        ..write(slashPrefixed ? '/' : '')
        ..write(cap)
        ..write(')?');
    } else {
      if (slashPrefixed) {
        outR.write('/');
        outS.write('/');
      }
      outR.write(cap);
      outS.write(cap);
    }
    names.add(name);
    groupCount++;
    groupIndexes.add(groupCount);
    groupCount += extraGroups;
  }

  void _writeLiteral(String literal, StringBuffer outR, StringBuffer outS) {
    staticChars += countStaticChars(literal);
    outR.write(RegExp.escape(literal));
    outS.write(RegExp.escape(caseSensitive ? literal : literal.toLowerCase()));
  }

  void _writeSegment(int start, int end) {
    var cursor = start, lastWasParam = false, hasLiteral = false, capCount = 0;
    while (cursor < end) {
      final c = pattern.codeUnitAt(cursor);
      if (c == asteriskCode) {
        _writeCapture(regex, shape, '([^/]*)', '${unnamedCount++}');
        needsCompiled = true;
        if (constraintScore < 1) constraintScore = 1;
        if (hasLiteral || ++capCount > 1) specificity = specStruct;
        cursor++;
        lastWasParam = false;
        continue;
      }
      if (c == colonCode) {
        cursor = _writeNamedCapture(cursor, end, lastWasParam, regex, shape);
        needsCompiled = true;
        if (hasLiteral || ++capCount > 1) specificity = specStruct;
        lastWasParam = true;
        continue;
      }
      final litStart = cursor++;
      while (cursor < end) {
        final cc = pattern.codeUnitAt(cursor);
        if (cc == colonCode || cc == asteriskCode) break;
        cursor++;
      }
      _writeLiteral(pattern.substring(litStart, cursor), regex, shape);
      hasLiteral = true;
      if (capCount > 0) specificity = specStruct;
      lastWasParam = false;
    }
  }

  bool writeGrouped(
    int start,
    int end,
    bool lastWasParam,
    StringBuffer outR,
    StringBuffer outS,
  ) {
    var cursor = start;
    while (cursor < end) {
      final c = pattern.codeUnitAt(cursor);
      if (c == openBraceCode) {
        final gEnd = _findGroupEnd(pattern, cursor);
        final optional =
            gEnd + 1 < pattern.length &&
            pattern.codeUnitAt(gEnd + 1) == questionCode;
        final bR = optional ? StringBuffer() : outR;
        final bS = optional ? StringBuffer() : outS;
        lastWasParam = writeGrouped(cursor + 1, gEnd, lastWasParam, bR, bS);
        if (optional) {
          bucket = bucketDeferred;
          if (constraintScore < 1) constraintScore = 1;
          outR
            ..write('(?:')
            ..write(bR)
            ..write(')?');
          outS
            ..write('(?:')
            ..write(bS)
            ..write(')?');
        }
        cursor = gEnd + (optional ? 2 : 1);
        needsCompiled = true;
        continue;
      }
      if (c == slashCode) {
        outR.write('/');
        outS.write('/');
        cursor++;
        lastWasParam = false;
        continue;
      }
      if (c == asteriskCode) {
        if (cursor + 1 < end &&
            pattern.codeUnitAt(cursor + 1) == asteriskCode) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        _writeCapture(outR, outS, '([^/]*)', '${unnamedCount++}');
        if (bucket < bucketLate) bucket = bucketLate;
        if (constraintScore < 1) constraintScore = 1;
        cursor++;
        lastWasParam = false;
        continue;
      }
      if (c == colonCode) {
        cursor = _writeNamedCapture(cursor, end, lastWasParam, outR, outS);
        lastWasParam = true;
        continue;
      }
      final litStart = cursor++;
      while (cursor < end) {
        final cc = pattern.codeUnitAt(cursor);
        if (cc == slashCode ||
            cc == colonCode ||
            cc == asteriskCode ||
            cc == openBraceCode ||
            cc == closeBraceCode) {
          break;
        }
        cursor++;
      }
      _writeLiteral(pattern.substring(litStart, cursor), outR, outS);
      lastWasParam = false;
    }
    return lastWasParam;
  }

  int _writeNamedCapture(
    int cursor,
    int end,
    bool lastWasParam,
    StringBuffer outR,
    StringBuffer outS,
  ) {
    if (lastWasParam) {
      throw FormatException('Unsupported segment syntax in route: $pattern');
    }
    var nameEnd = cursor + 1;
    while (nameEnd < end &&
        isParamCode(pattern.codeUnitAt(nameEnd), nameEnd == cursor + 1)) {
      nameEnd++;
    }
    final name = pattern.substring(cursor + 1, nameEnd);
    if (!validParamSlice(name, 0, name.length)) {
      throw FormatException('Invalid parameter name in route: $pattern');
    }
    if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
      final regexEnd = _findRegexEnd(pattern, nameEnd, end);
      final body = pattern.substring(nameEnd + 1, regexEnd);
      if (constraintScore < 2) constraintScore = 2;
      _writeCapture(
        outR,
        outS,
        '($body)',
        name,
        extraGroups: _countCapturingGroups(body),
      );
      return regexEnd + 1;
    }
    _writeCapture(outR, outS, '([^/]+)', name);
    return nameEnd;
  }
}

// ── pattern compiler helpers ───────────────────────────────────────────────

bool _containsStructuredBrace(String pattern) {
  const backslash = 92, zero = 48, nine = 57;
  for (var i = 0; i < pattern.length; i++) {
    if (pattern.codeUnitAt(i) != openBraceCode) continue;
    if (i > 0 && pattern.codeUnitAt(i - 1) == backslash) continue;
    if (i + 1 >= pattern.length) return true;
    final next = pattern.codeUnitAt(i + 1);
    if (next >= zero && next <= nine) continue;
    return true;
  }
  return false;
}

int _findGroupEnd(String pattern, int start) {
  var depth = 0;
  for (var i = start; i < pattern.length; i++) {
    final c = pattern.codeUnitAt(i);
    if (c == openBraceCode) depth++;
    if (c == closeBraceCode && --depth == 0) return i;
  }
  throw FormatException('Unclosed group in route: $pattern');
}

int _findRegexEnd(String pattern, int start, int segEnd) {
  var depth = 0, escaped = false, inClass = false;
  for (var i = start; i < segEnd; i++) {
    final c = pattern.codeUnitAt(i);
    if (escaped) {
      escaped = false;
    } else if (c == 92) {
      escaped = true;
    } else if (inClass) {
      if (c == 93) inClass = false;
    } else if (c == 91) {
      inClass = true;
    } else if (c == 40) {
      depth++;
    } else if (c == 41 && --depth == 0) {
      return i;
    }
  }
  throw FormatException('Unclosed regex in route: $pattern');
}

int _countCapturingGroups(String body) {
  var count = 0, escaped = false, inClass = false;
  for (var i = 0; i < body.length; i++) {
    final c = body.codeUnitAt(i);
    if (escaped) {
      escaped = false;
    } else if (c == 92) {
      escaped = true;
    } else if (inClass) {
      if (c == 93) inClass = false;
    } else if (c == 91) {
      inClass = true;
    } else if (c == 40) {
      if (i + 1 < body.length && body.codeUnitAt(i + 1) == questionCode) {
        if (i + 2 >= body.length) continue;
        final marker = body.codeUnitAt(i + 2);
        if (marker == colonCode || marker == 61 || marker == 33) continue;
        if (marker == 60) {
          if (i + 3 < body.length) {
            final next = body.codeUnitAt(i + 3);
            if (next == 61 || next == 33) continue;
          }
          count++;
        }
        continue;
      }
      count++;
    }
  }
  return count;
}
