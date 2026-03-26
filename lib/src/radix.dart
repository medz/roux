// Single radix trie — nodes carry typed fields; no edge-list scanning.
// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'path.dart';

// ── node ──────────────────────────────────────────────────────────────────────

class _Node<T> {
  final Map<String, _Node<T>> statics = {};
  _ParamEdge<T>? param;
  _CatchAllEdge<T>? catchAll;
  List<_PatternEdge<T>>? highPats; // bucketHigh  — before :param
  List<_PatternEdge<T>>? loPats; // bucketLate/Repeat — after :param
  List<_PatternEdge<T>>? deferPats; // bucketDeferred — last
  MethodSlot<T>? slot;
}

// ── edges ─────────────────────────────────────────────────────────────────────

class _ParamEdge<T> {
  final _Node<T> child = _Node<T>();
}

class _CatchAllEdge<T> {
  final MethodSlot<T> slot;
  _CatchAllEdge(this.slot);
}

class _PatternEdge<T> {
  final RegExp regex;
  final String shape;
  final int bucket;
  final List<int> groupIndexes;
  MethodSlot<T> slot;
  _PatternEdge(
    this.regex,
    this.shape,
    this.bucket,
    this.groupIndexes,
    this.slot,
  );
}

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
          final dupPrefix = cursor == 1 && names.isEmpty
              ? dupFallback
              : dupWildcard;
          (node.catchAll ??= _CatchAllEdge(
            MethodSlot<T>(),
          )).slot.add(method, entry, policy, norm, dupPrefix);
          return;
        }
      }

      // Simple :name param
      if (firstCode == colonCode && !segComplex) {
        if (!validParamSlice(norm, cursor + 1, segEnd)) break;
        node = (node.param ??= _ParamEdge<T>()).child;
        names.add(norm.substring(cursor + 1, segEnd));
        depth++;
        cursor = segEnd < norm.length ? segEnd + 1 : norm.length;
        continue;
      }

      // Complex segment
      if (segComplex || firstCode == colonCode || firstCode == asteriskCode) {
        break;
      }

      // Static segment
      final key = caseSensitive
          ? norm.substring(cursor, segEnd)
          : norm.substring(cursor, segEnd).toLowerCase();
      staticChars += segEnd - cursor;
      node = node.statics.putIfAbsent(key, _Node.new);
      depth++;
      cursor = segEnd < norm.length ? segEnd + 1 : norm.length;
    }

    if (cursor >= norm.length) {
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
      final list = _patList(node, compiled.bucket);
      for (final p in list) {
        if (p.shape == compiled.shape) {
          p.slot.add(method, compiled.entry, policy, norm, dupShape);
          return;
        }
      }
      _addPattern(
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
    final entry = RouteEntry<T>(
      data,
      const [],
      null,
      specExact,
      countSegments(path),
      countStaticChars(path) - 1,
      0,
      order,
    );
    final key = caseSensitive ? path : path.toLowerCase();
    (_exact[key] ??= MethodSlot<T>()).add(
      method,
      entry,
      policy,
      path,
      dupShape,
    );
  }

  List<_PatternEdge<T>> _patList(_Node<T> node, int bucket) =>
      bucket == bucketHigh
      ? (node.highPats ??= [])
      : bucket == bucketDeferred
      ? (node.deferPats ??= [])
      : (node.loPats ??= []);

  void _addPattern(_Node<T> node, _PatternEdge<T> edge) {
    final list = _patList(node, edge.bucket);
    final ne = edge.slot.any;
    if (ne != null) {
      for (var i = 0; i < list.length; i++) {
        final ce = list[i].slot.any;
        if (ce != null &&
            (ne.rank > ce.rank ||
                (ne.rank == ce.rank && ne.order < ce.order))) {
          list.insert(i, edge);
          return;
        }
      }
    }
    list.add(edge);
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

  RouteMatch<T>? _tryPats(
    List<_PatternEdge<T>>? pats,
    String path,
    String? method,
  ) {
    for (final p in pats ?? []) {
      final m = p.regex.firstMatch(path);
      if (m == null) continue;
      final e = p.slot.lookup(method);
      if (e != null) return _materializePattern(e, p.groupIndexes, m);
    }
    return null;
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
      return _tryPats(node.highPats, path, method) ??
          _tryPats(node.loPats, path, method) ??
          (node.catchAll?.slot
              .lookup(method)
              ?.materialize(captures, remainder: '')) ??
          _tryPats(node.deferPats, path, method);
    }

    final segEnd = findSegmentEnd(path, cursor);
    if (segEnd == cursor) return null;
    final next = segEnd < path.length ? segEnd + 1 : path.length;
    final seg = caseSensitive
        ? path.substring(cursor, segEnd)
        : path.substring(cursor, segEnd).toLowerCase();

    final staticChild = node.statics[seg];
    if (staticChild != null) {
      final m = _walk(staticChild, path, method, next, captures);
      if (m != null) return m;
    }

    return _tryPats(node.highPats, path, method) ??
        (node.param == null
            ? null
            : _walk(node.param!.child, path, method, next, [
                ...captures,
                path.substring(cursor, segEnd),
              ])) ??
        _tryPats(node.loPats, path, method) ??
        (node.catchAll?.slot
            .lookup(method)
            ?.materialize(captures, remainder: path.substring(cursor))) ??
        _tryPats(node.deferPats, path, method);
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

  void _collectPats(
    List<_PatternEdge<T>>? pats,
    String path,
    String? method,
    MatchAccumulator<T> acc,
  ) {
    for (final p in pats ?? []) {
      final m = p.regex.firstMatch(path);
      if (m == null) continue;
      p.slot.collect(method, (entry, mr) {
        RouteEntry<T>? e = entry;
        while (e != null) {
          acc.add(
            _materializePattern(e, p.groupIndexes, m),
            e.rank,
            mr,
            e.order,
          );
          e = e.next;
        }
      });
    }
  }

  void _walkCollect(
    _Node<T> node,
    String path,
    String? method,
    int cursor,
    List<String> captures,
    MatchAccumulator<T> acc,
  ) {
    // Catch-all matches at any depth
    if (node.catchAll != null) {
      final remainder = cursor >= path.length ? '' : path.substring(cursor);
      node.catchAll!.slot.collect(method, (entry, mr) {
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
    }

    // Pattern edges at this node
    _collectPats(node.highPats, path, method, acc);
    _collectPats(node.loPats, path, method, acc);
    _collectPats(node.deferPats, path, method, acc);

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
    final seg = caseSensitive
        ? path.substring(cursor, segEnd)
        : path.substring(cursor, segEnd).toLowerCase();

    final staticChild = node.statics[seg];
    if (staticChild != null) {
      _walkCollect(staticChild, path, method, next, captures, acc);
    }
    if (node.param != null) {
      _walkCollect(node.param!.child, path, method, next, [
        ...captures,
        path.substring(cursor, segEnd),
      ], acc);
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
  _PatternCompiler(this.pattern, this.data, this.caseSensitive, this.order) {
    _cur = (regex, shape);
  }

  final String pattern;
  final T data;
  final bool caseSensitive;
  final int order;

  final regex = StringBuffer('^'), shape = StringBuffer('^');
  late (StringBuffer, StringBuffer) _cur;
  final names = <String>[], groupIndexes = <int>[];
  var groupCount = 0, unnamedCount = 0, staticChars = 0;
  var needsCompiled = false, bucket = bucketHigh;
  var specificity = specDyn, constraintScore = 0;

  void _write(String v) {
    _cur.$1.write(v);
    _cur.$2.write(v);
  }

  _Compiled<T>? compile() {
    if (_containsStructuredBrace(pattern)) {
      needsCompiled = true;
      specificity = specStruct;
      if (constraintScore < 1) constraintScore = 1;
      writeGrouped(0, pattern.length, false);
      _write(r'$');
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
          '([^/]+)',
          pattern.substring(cursor + 1, segEnd),
          slashPrefixed: true,
        );
        cursor = segEnd + 1;
        continue;
      }
      if (segEnd - cursor == 1 && first == asteriskCode) {
        _writeCapture('([^/]+)', '${unnamedCount++}', slashPrefixed: true);
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
      _write('/');
      _writeSegment(cursor, segEnd);
      cursor = segEnd + 1;
    }
    _write(r'$');
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
    String cap,
    String name, {
    int extraGroups = 0,
    bool slashPrefixed = false,
    bool optional = false,
  }) {
    if (optional) {
      _write('(?:');
      if (slashPrefixed) _write('/');
      _write(cap);
      _write(')?');
    } else {
      if (slashPrefixed) _write('/');
      _write(cap);
    }
    names.add(name);
    groupCount++;
    groupIndexes.add(groupCount);
    groupCount += extraGroups;
  }

  void _writeLiteral(String literal) {
    staticChars += countStaticChars(literal);
    _cur.$1.write(RegExp.escape(literal));
    _cur.$2.write(
      RegExp.escape(caseSensitive ? literal : literal.toLowerCase()),
    );
  }

  void _writeSegment(int start, int end) {
    var cursor = start, lastWasParam = false, hasLiteral = false, capCount = 0;
    while (cursor < end) {
      final c = pattern.codeUnitAt(cursor);
      if (c == asteriskCode) {
        _writeCapture('([^/]*)', '${unnamedCount++}');
        needsCompiled = true;
        if (constraintScore < 1) constraintScore = 1;
        if (hasLiteral || ++capCount > 1) specificity = specStruct;
        cursor++;
        lastWasParam = false;
        continue;
      }
      if (c == colonCode) {
        cursor = _writeNamedCapture(cursor, end, lastWasParam);
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
      _writeLiteral(pattern.substring(litStart, cursor));
      hasLiteral = true;
      if (capCount > 0) specificity = specStruct;
      lastWasParam = false;
    }
  }

  bool writeGrouped(int start, int end, bool lastWasParam) {
    var cursor = start;
    while (cursor < end) {
      final c = pattern.codeUnitAt(cursor);
      if (c == openBraceCode) {
        final gEnd = _findGroupEnd(pattern, cursor);
        final optional =
            gEnd + 1 < pattern.length &&
            pattern.codeUnitAt(gEnd + 1) == questionCode;
        if (optional) {
          final saved = _cur;
          _cur = (StringBuffer(), StringBuffer());
          lastWasParam = writeGrouped(cursor + 1, gEnd, lastWasParam);
          final tmpR = _cur.$1, tmpS = _cur.$2;
          _cur = saved;
          bucket = bucketDeferred;
          if (constraintScore < 1) constraintScore = 1;
          saved.$1
            ..write('(?:')
            ..write(tmpR)
            ..write(')?');
          saved.$2
            ..write('(?:')
            ..write(tmpS)
            ..write(')?');
        } else {
          lastWasParam = writeGrouped(cursor + 1, gEnd, lastWasParam);
        }
        cursor = gEnd + (optional ? 2 : 1);
        needsCompiled = true;
        continue;
      }
      if (c == slashCode) {
        _write('/');
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
        _writeCapture('([^/]*)', '${unnamedCount++}');
        if (bucket < bucketLate) bucket = bucketLate;
        if (constraintScore < 1) constraintScore = 1;
        cursor++;
        lastWasParam = false;
        continue;
      }
      if (c == colonCode) {
        cursor = _writeNamedCapture(cursor, end, lastWasParam);
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
      _writeLiteral(pattern.substring(litStart, cursor));
      lastWasParam = false;
    }
    return lastWasParam;
  }

  int _writeNamedCapture(int cursor, int end, bool lastWasParam) {
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
      _writeCapture('($body)', name, extraGroups: _countCapturingGroups(body));
      return regexEnd + 1;
    }
    _writeCapture('([^/]+)', name);
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
