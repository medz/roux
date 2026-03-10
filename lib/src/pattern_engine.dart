import 'route_model.dart';
import 'route_path.dart';

class PatternEngine<T> {
  PatternEngine(this.caseSensitive);

  final bool caseSensitive;
  bool hasRoutes = false;
  final List<List<CompiledSlot<T>>> buckets = List.generate(
    4,
    (_) => [],
    growable: false,
  );

  void add(
    String pattern,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
  ) {
    final compiled = _PatternCompiler(
      pattern,
      data,
      caseSensitive,
      registrationOrder,
    ).compile();
    if (compiled == null)
      throw FormatException('Unsupported segment syntax in route: $pattern');
    addCompiled(compiled, pattern, duplicatePolicy);
  }

  RouteMatch<T>? matchBucket(int bucket, String path) {
    for (final current in buckets[bucket]) {
      final match = current.regex.firstMatch(path);
      if (match != null)
        return materializeCompiled(current.route, current.groupIndexes, match);
    }
    return null;
  }

  void collectBucket(
    int bucket,
    String path,
    int methodRank,
    MatchAccumulator<T> output,
  ) {
    for (final current in buckets[bucket]) {
      final match = current.regex.firstMatch(path);
      if (match == null) continue;
      for (
        RouteEntry<T>? route = current.route;
        route != null;
        route = route.next
      ) {
        output.add(
          materializeCompiled(route, current.groupIndexes, match),
          route,
          methodRank,
        );
      }
    }
  }

  void addCompiled(
    CompiledSlot<T> compiled,
    String pattern,
    DuplicatePolicy duplicatePolicy,
  ) {
    hasRoutes = true;
    final routes = buckets[compiled.bucket];
    for (var i = 0; i < routes.length; i++) {
      final current = routes[i];
      if (current.shape == compiled.shape) {
        current.route = mergeRouteEntries(
          current.route,
          compiled.route,
          pattern,
          duplicatePolicy,
          dupShape,
        );
        return;
      }
      if (compiled.route.sortKey > current.route.sortKey ||
          (compiled.route.sortKey == current.route.sortKey &&
              compiled.route.registrationOrder <
                  current.route.registrationOrder)) {
        routes.insert(i, compiled);
        return;
      }
    }
    routes.add(compiled);
  }
}

class CompiledSlot<T> {
  final RegExp regex;
  final String shape;
  final int bucket;
  final List<int> groupIndexes;
  RouteEntry<T> route;

  CompiledSlot(
    this.regex,
    this.shape,
    this.bucket,
    this.groupIndexes,
    this.route,
  );
}

RouteMatch<T> materializeCompiled<T>(
  RouteEntry<T> route,
  List<int> groupIndexes,
  RegExpMatch match,
) {
  if (route.paramNames.isEmpty) return route.noParamsMatch;
  final params = <String, String>{};
  for (var i = 0; i < route.paramNames.length; i++) {
    final groupIndex = groupIndexes[i];
    if (groupIndex < 0) continue;
    final value = match.group(groupIndex);
    if (value != null) params[route.paramNames[i]] = value;
  }
  return RouteMatch(route.data, params);
}

class _PatternCompiler<T> {
  _PatternCompiler(
    this.pattern,
    this.data,
    this.caseSensitive,
    this.registrationOrder,
  );

  final String pattern;
  final T data;
  final bool caseSensitive;
  final int registrationOrder;
  final regex = StringBuffer('^'), shape = StringBuffer('^');
  final paramNames = <String>[], groupIndexes = <int>[];
  var groupCount = 0, unnamedCount = 0, staticChars = 0;
  var needsCompiled = false;
  var bucket = compiledBucketHigh;
  var specificity = singleDynamicSpecificity;
  var constraintScore = 0;

  CompiledSlot<T>? compile() {
    if (pattern.contains('{')) {
      writeGrouped(0, pattern.length, false, regex, shape);
      regex.write(r'$');
      shape.write(r'$');
      return CompiledSlot(
        RegExp(regex.toString(), caseSensitive: caseSensitive),
        shape.toString(),
        compiledBucketDeferred,
        groupIndexes,
        newRoute(
          data,
          paramNames,
          null,
          pattern,
          segmentCount(pattern),
          structuredDynamicSpecificity,
          staticChars,
          1,
          registrationOrder,
        ),
      );
    }
    for (
      var cursor = pattern.length == 1 ? pattern.length : 1;
      cursor < pattern.length;
    ) {
      final segmentEnd = findSegmentEnd(pattern, cursor);
      final firstCode = pattern.codeUnitAt(cursor);
      if (segmentEnd == cursor) throw FormatException('$emptySegment$pattern');
      if (firstCode == colonCode &&
          hasValidParamNameSlice(pattern, cursor + 1, segmentEnd)) {
        writeCapture(
          regex,
          shape,
          '([^/]+)',
          pattern.substring(cursor + 1, segmentEnd),
          slashPrefixed: true,
        );
        cursor = segmentEnd + 1;
        continue;
      }
      if (segmentEnd - cursor == 1 && firstCode == asteriskCode) {
        writeCapture(
          regex,
          shape,
          '([^/]+)',
          '${unnamedCount++}',
          slashPrefixed: true,
        );
        needsCompiled = true;
        bucket = compiledBucketLate;
        constraintScore = 1;
        cursor = segmentEnd + 1;
        continue;
      }
      if (firstCode == colonCode) {
        final quantifier = pattern.codeUnitAt(segmentEnd - 1);
        if (quantifier == questionCode ||
            quantifier == plusCode ||
            quantifier == asteriskCode) {
          final name = pattern.substring(cursor + 1, segmentEnd - 1);
          if (!isValidParamName(name)) {
            throw FormatException('Invalid parameter name in route: $pattern');
          }
          if (quantifier == questionCode) {
            writeCapture(
              regex,
              shape,
              '([^/]+)',
              name,
              slashPrefixed: true,
              optional: true,
            );
            needsCompiled = true;
            bucket = compiledBucketDeferred;
            specificity = structuredDynamicSpecificity;
            constraintScore = 1;
          } else {
            writeCapture(
              regex,
              shape,
              quantifier == plusCode ? '(.+(?:/.+)*)' : '(.*)',
              name,
              slashPrefixed: true,
              optional: quantifier != plusCode,
            );
            needsCompiled = true;
            bucket = compiledBucketRepeated;
            specificity = remainderSpecificity;
            constraintScore = 1;
          }
          cursor = segmentEnd + 1;
          continue;
        }
      }
      regex.write('/');
      shape.write('/');
      writeSegment(cursor, segmentEnd);
      cursor = segmentEnd + 1;
    }
    regex.write(r'$');
    shape.write(r'$');
    if (!needsCompiled) return null;
    return CompiledSlot(
      RegExp(regex.toString(), caseSensitive: caseSensitive),
      shape.toString(),
      bucket,
      groupIndexes,
      newRoute(
        data,
        paramNames,
        null,
        pattern,
        segmentCount(pattern),
        specificity,
        staticChars,
        constraintScore,
        registrationOrder,
      ),
    );
  }

  void writeCapture(
    StringBuffer outRegex,
    StringBuffer outShape,
    String capture,
    String name, {
    int extraGroups = 0,
    bool slashPrefixed = false,
    bool optional = false,
  }) {
    if (optional) {
      outRegex
        ..write('(?:')
        ..write(slashPrefixed ? '/' : '')
        ..write(capture)
        ..write(')?');
      outShape
        ..write('(?:')
        ..write(slashPrefixed ? '/' : '')
        ..write(capture)
        ..write(')?');
    } else {
      if (slashPrefixed) {
        outRegex.write('/');
        outShape.write('/');
      }
      outRegex.write(capture);
      outShape.write(capture);
    }
    paramNames.add(name);
    groupCount += 1;
    groupIndexes.add(groupCount);
    groupCount += extraGroups;
  }

  void writeLiteral(
    String literal,
    StringBuffer outRegex,
    StringBuffer outShape,
  ) {
    staticChars += staticCharCount(literal);
    outRegex.write(RegExp.escape(literal));
    outShape.write(
      RegExp.escape(caseSensitive ? literal : literal.toLowerCase()),
    );
  }

  void writeSegment(int start, int end) {
    var cursor = start;
    var lastWasParam = false;
    var segmentHasLiteral = false;
    var captureCount = 0;
    while (cursor < end) {
      final code = pattern.codeUnitAt(cursor);
      if (code == asteriskCode) {
        writeCapture(regex, shape, '([^/]*)', '${unnamedCount++}');
        needsCompiled = true;
        if (constraintScore < 1) constraintScore = 1;
        if (segmentHasLiteral || ++captureCount > 1) {
          specificity = structuredDynamicSpecificity;
        }
        cursor += 1;
        lastWasParam = false;
        continue;
      }
      if (code == colonCode) {
        cursor = writeNamedCapture(cursor, end, lastWasParam, regex, shape);
        needsCompiled = true;
        if (segmentHasLiteral || ++captureCount > 1) {
          specificity = structuredDynamicSpecificity;
        }
        lastWasParam = true;
        continue;
      }
      final literalStart = cursor;
      cursor += 1;
      while (cursor < end) {
        final code = pattern.codeUnitAt(cursor);
        if (code == colonCode || code == asteriskCode) break;
        cursor += 1;
      }
      writeLiteral(pattern.substring(literalStart, cursor), regex, shape);
      segmentHasLiteral = true;
      if (captureCount > 0) specificity = structuredDynamicSpecificity;
      lastWasParam = false;
    }
  }

  bool writeGrouped(
    int start,
    int end,
    bool lastWasParam,
    StringBuffer outRegex,
    StringBuffer outShape,
  ) {
    var cursor = start;
    while (cursor < end) {
      final code = pattern.codeUnitAt(cursor);
      if (code == openBraceCode) {
        final groupEnd = findGroupEnd(pattern, cursor);
        final optional =
            groupEnd + 1 < pattern.length &&
            pattern.codeUnitAt(groupEnd + 1) == questionCode;
        if (optional) {
          final bodyRegex = StringBuffer();
          final bodyShape = StringBuffer();
          lastWasParam = writeGrouped(
            cursor + 1,
            groupEnd,
            lastWasParam,
            bodyRegex,
            bodyShape,
          );
          outRegex
            ..write('(?:')
            ..write(bodyRegex)
            ..write(')?');
          outShape
            ..write('(?:')
            ..write(bodyShape)
            ..write(')?');
          cursor = groupEnd + 2;
        } else {
          lastWasParam = writeGrouped(
            cursor + 1,
            groupEnd,
            lastWasParam,
            outRegex,
            outShape,
          );
          cursor = groupEnd + 1;
        }
        needsCompiled = true;
        continue;
      }
      if (code == slashCode) {
        outRegex.write('/');
        outShape.write('/');
        cursor += 1;
        lastWasParam = false;
        continue;
      }
      if (code == asteriskCode) {
        if (cursor + 1 < end &&
            pattern.codeUnitAt(cursor + 1) == asteriskCode) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        writeCapture(outRegex, outShape, '([^/]*)', '${unnamedCount++}');
        cursor += 1;
        lastWasParam = false;
        continue;
      }
      if (code == colonCode) {
        cursor = writeNamedCapture(
          cursor,
          end,
          lastWasParam,
          outRegex,
          outShape,
        );
        lastWasParam = true;
        continue;
      }
      final literalStart = cursor;
      cursor += 1;
      while (cursor < end) {
        final code = pattern.codeUnitAt(cursor);
        if (code == slashCode ||
            code == colonCode ||
            code == asteriskCode ||
            code == openBraceCode ||
            code == closeBraceCode) {
          break;
        }
        cursor += 1;
      }
      writeLiteral(pattern.substring(literalStart, cursor), outRegex, outShape);
      lastWasParam = false;
    }
    return lastWasParam;
  }

  int writeNamedCapture(
    int cursor,
    int end,
    bool lastWasParam,
    StringBuffer outRegex,
    StringBuffer outShape,
  ) {
    if (lastWasParam) {
      throw FormatException('Unsupported segment syntax in route: $pattern');
    }
    var nameEnd = cursor + 1;
    while (nameEnd < end &&
        isParamNameCode(pattern.codeUnitAt(nameEnd), nameEnd == cursor + 1)) {
      nameEnd += 1;
    }
    final name = pattern.substring(cursor + 1, nameEnd);
    if (!isValidParamName(name)) {
      throw FormatException('Invalid parameter name in route: $pattern');
    }
    if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
      final regexEnd = findRegexEnd(pattern, nameEnd, end);
      final body = pattern.substring(nameEnd + 1, regexEnd);
      if (constraintScore < 2) constraintScore = 2;
      writeCapture(
        outRegex,
        outShape,
        '($body)',
        name,
        extraGroups: countCapturingGroups(body),
      );
      return regexEnd + 1;
    }
    writeCapture(outRegex, outShape, '([^/]+)', name);
    return nameEnd;
  }
}

int findGroupEnd(String pattern, int start) {
  var depth = 0;
  for (var i = start; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);
    if (code == openBraceCode) depth += 1;
    if (code == closeBraceCode && --depth == 0) return i;
  }
  throw FormatException('Unclosed group in route: $pattern');
}

int findRegexEnd(String pattern, int start, int segmentEnd) {
  var depth = 0;
  var escaped = false;
  for (var i = start; i < segmentEnd; i++) {
    final code = pattern.codeUnitAt(i);
    if (escaped) {
      escaped = false;
    } else if (code == 92) {
      escaped = true;
    } else if (code == 40) {
      depth += 1;
    } else if (code == 41 && --depth == 0) {
      return i;
    }
  }
  throw FormatException('Unclosed regex in route: $pattern');
}

int countCapturingGroups(String body) {
  var count = 0;
  var escaped = false;
  for (var i = 0; i < body.length; i++) {
    final code = body.codeUnitAt(i);
    if (escaped) {
      escaped = false;
    } else if (code == 92) {
      escaped = true;
    } else if (code == 40 &&
        (i + 1 >= body.length || body.codeUnitAt(i + 1) != questionCode)) {
      count += 1;
    }
  }
  return count;
}
