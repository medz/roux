import 'input_path.dart';
import 'route_entry.dart';
import 'specificity.dart';
import 'types.dart';

class PatternEngine<T> {
  PatternEngine(this.caseSensitive);

  final bool caseSensitive;
  final List<CompiledSlot<T>?> heads = List<CompiledSlot<T>?>.filled(4, null);

  bool get hasAny =>
      heads[0] != null ||
      heads[1] != null ||
      heads[2] != null ||
      heads[3] != null;

  bool get needsSpecificitySort => hasAny;

  void add(
    String pattern,
    T data,
    DuplicatePolicy duplicatePolicy,
    int registrationOrder,
  ) {
    final compiled = compilePatternRoute(
      pattern,
      data,
      caseSensitive,
      registrationOrder,
    );
    if (compiled == null) {
      throw FormatException('Unsupported segment syntax in route: $pattern');
    }
    addCompiled(compiled, pattern, duplicatePolicy);
  }

  RouteMatch<T>? matchHead(CompiledSlot<T> head, String path) {
    var current = head;
    while (true) {
      final match = current.regex.firstMatch(path);
      if (match != null) {
        return materializeCompiled(current.route, current.groupIndexes, match);
      }
      final next = current.next;
      if (next == null) return null;
      current = next;
    }
  }

  void collectHead(
    CompiledSlot<T> head,
    String path,
    int methodRank,
    MatchCollector<T> output,
  ) {
    var current = head;
    while (true) {
      final match = current.regex.firstMatch(path);
      if (match != null) {
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
      final next = current.next;
      if (next == null) return;
      current = next;
    }
  }

  void addCompiled(
    CompiledSlot<T> compiled,
    String pattern,
    DuplicatePolicy duplicatePolicy,
  ) {
    final bucket = compiled.bucket;
    if (bucket < 0 || bucket >= heads.length) {
      throw StateError('Invalid compiled bucket: $bucket');
    }
    final head = heads[bucket];
    if (head == null) {
      heads[bucket] = compiled;
      return;
    }
    if (head.shape == compiled.shape) {
      verifyCompiledNames(
        head.route.paramNames,
        compiled.route.paramNames,
        pattern,
      );
      head.route = mergeRouteEntries(
        head.route,
        compiled.route,
        pattern,
        duplicatePolicy,
        dupShape,
      );
      return;
    }
    if (compiledSortsBefore(compiled.route, head.route)) {
      compiled.next = head;
      heads[bucket] = compiled;
      return;
    }
    for (var current = head; ; current = current.next!) {
      final next = current.next;
      if (next == null) {
        current.next = compiled;
        return;
      }
      if (next.shape == compiled.shape) {
        verifyCompiledNames(
          next.route.paramNames,
          compiled.route.paramNames,
          pattern,
        );
        next.route = mergeRouteEntries(
          next.route,
          compiled.route,
          pattern,
          duplicatePolicy,
          dupShape,
        );
        return;
      }
      if (compiledSortsBefore(compiled.route, next.route)) {
        compiled.next = next;
        current.next = compiled;
        return;
      }
    }
  }
}

class CompiledSlot<T> {
  final RegExp regex;
  final String shape;
  final int bucket;
  final List<int> groupIndexes;
  RouteEntry<T> route;
  CompiledSlot<T>? next;

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
  return RouteMatch<T>(route.data, params);
}

CompiledSlot<T>? compilePatternRoute<T>(
  String pattern,
  T data,
  bool caseSensitive,
  int registrationOrder,
) => _PatternCompiler<T>(
  pattern,
  data,
  caseSensitive,
  registrationOrder,
).compile();

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
  final regex = StringBuffer('^');
  final shape = StringBuffer('^');
  final paramNames = <String>[];
  final groupIndexes = <int>[];
  var groupCount = 0;
  var unnamedCount = 0;
  var staticChars = 0;
  var needsCompiled = false;
  var bucket = compiledBucketHigh;
  var specificity = singleDynamicSpecificity;
  var constraintScore = 0;

  CompiledSlot<T>? compile() {
    if (pattern.contains('{')) {
      writeGrouped(0, pattern.length, false, regex, shape);
      return finish(
        needsCompiled: true,
        bucket: compiledBucketDeferred,
        specificity: structuredDynamicSpecificity,
        constraintScore: 1,
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
        addCapture('([^/]+)', pattern.substring(cursor + 1, segmentEnd));
        cursor = segmentEnd + 1;
        continue;
      }
      if (segmentEnd - cursor == 1 && firstCode == asteriskCode) {
        addCapture('([^/]+)', '${unnamedCount++}');
        needsCompiled = true;
        bucket = compiledBucketLate;
        constraintScore = 1;
        cursor = segmentEnd + 1;
        continue;
      }
      final repeated = readRepeatedParam(pattern, cursor, segmentEnd);
      if (repeated != null) {
        final plus = repeated.$2 == plusCode;
        addCapture(plus ? '(.+(?:/.+)*)' : '(.*)', repeated.$1, wrap: !plus);
        needsCompiled = true;
        bucket = compiledBucketRepeated;
        specificity = remainderSpecificity;
        constraintScore = 1;
        cursor = segmentEnd + 1;
        continue;
      }
      final optional = readOptionalParamName(pattern, cursor, segmentEnd);
      if (optional != null) {
        addCapture('([^/]+)', optional, wrap: true);
        needsCompiled = true;
        bucket = compiledBucketDeferred;
        specificity = structuredDynamicSpecificity;
        constraintScore = 1;
        cursor = segmentEnd + 1;
        continue;
      }
      regex.write('/');
      shape.write('/');
      writeSegment(cursor, segmentEnd);
      cursor = segmentEnd + 1;
    }
    return finish(
      needsCompiled: needsCompiled,
      bucket: bucket,
      specificity: specificity,
      constraintScore: constraintScore,
    );
  }

  CompiledSlot<T>? finish({
    required bool needsCompiled,
    required int bucket,
    required int specificity,
    required int constraintScore,
  }) {
    regex.write(r'$');
    shape.write(r'$');
    if (!needsCompiled) return null;
    validateCaptureNames(paramNames, null, pattern);
    return CompiledSlot<T>(
      RegExp(regex.toString(), caseSensitive: caseSensitive),
      shape.toString(),
      bucket,
      groupIndexes,
      RouteEntry<T>(
        data,
        paramNames,
        null,
        pathDepth(pattern),
        specificity,
        staticChars,
        constraintScore,
        registrationOrder,
      ),
    );
  }

  void addCapture(String capture, String name, {bool wrap = false}) {
    if (wrap) {
      regex
        ..write('(?:/')
        ..write(capture)
        ..write(')?');
      shape
        ..write('(?:/')
        ..write(capture)
        ..write(')?');
    } else {
      regex
        ..write('/')
        ..write(capture);
      shape
        ..write('/')
        ..write(capture);
    }
    paramNames.add(name);
    groupCount += 1;
    groupIndexes.add(groupCount);
  }

  void addInlineCapture(String capture, String name, {int extraGroups = 0}) {
    writeInlineCapture(regex, shape, capture, name, extraGroups: extraGroups);
  }

  void writeInlineCapture(
    StringBuffer outRegex,
    StringBuffer outShape,
    String capture,
    String name, {
    int extraGroups = 0,
  }) {
    outRegex.write(capture);
    outShape.write(capture);
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
    staticChars += literalCharCount(literal);
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
        addInlineCapture('([^/]*)', '${unnamedCount++}');
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
        if (lastWasParam) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        var nameEnd = cursor + 1;
        while (nameEnd < end &&
            isParamNameCode(
              pattern.codeUnitAt(nameEnd),
              nameEnd == cursor + 1,
            )) {
          nameEnd += 1;
        }
        final name = pattern.substring(cursor + 1, nameEnd);
        if (!isValidParamName(name)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
          final regexEnd = findRegexEnd(pattern, nameEnd, end);
          final body = pattern.substring(nameEnd + 1, regexEnd);
          addInlineCapture(
            '($body)',
            name,
            extraGroups: countCapturingGroups(body),
          );
          if (constraintScore < 2) constraintScore = 2;
          cursor = regexEnd + 1;
        } else {
          addInlineCapture('([^/]+)', name);
          cursor = nameEnd;
        }
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
        writeInlineCapture(outRegex, outShape, '([^/]*)', '${unnamedCount++}');
        cursor += 1;
        lastWasParam = false;
        continue;
      }
      if (code == colonCode) {
        if (lastWasParam) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        var nameEnd = cursor + 1;
        while (nameEnd < end &&
            isParamNameCode(
              pattern.codeUnitAt(nameEnd),
              nameEnd == cursor + 1,
            )) {
          nameEnd += 1;
        }
        final name = pattern.substring(cursor + 1, nameEnd);
        if (!isValidParamName(name)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
          final regexEnd = findRegexEnd(pattern, nameEnd, end);
          final body = pattern.substring(nameEnd + 1, regexEnd);
          writeInlineCapture(
            outRegex,
            outShape,
            '($body)',
            name,
            extraGroups: countCapturingGroups(body),
          );
          cursor = regexEnd + 1;
        } else {
          writeInlineCapture(outRegex, outShape, '([^/]+)', name);
          cursor = nameEnd;
        }
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
}

void verifyCompiledNames(List<String> a, List<String> b, String pattern) {
  if (a.length != b.length) throw FormatException('$dupShape$pattern');
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw FormatException('$dupShape$pattern');
  }
}

String? readOptionalParamName(String pattern, int start, int end) {
  if (pattern.codeUnitAt(start) != colonCode ||
      pattern.codeUnitAt(end - 1) != questionCode) {
    return null;
  }
  final name = pattern.substring(start + 1, end - 1);
  return isValidParamName(name) ? name : null;
}

(String, int)? readRepeatedParam(String pattern, int start, int end) {
  if (pattern.codeUnitAt(start) != colonCode) return null;
  final quantifier = pattern.codeUnitAt(end - 1);
  if (quantifier != questionCode &&
      quantifier != plusCode &&
      quantifier != asteriskCode) {
    return null;
  }
  if (quantifier == questionCode) return null;
  final name = pattern.substring(start + 1, end - 1);
  return isValidParamName(name) ? (name, quantifier) : null;
}

int findGroupEnd(String pattern, int start) {
  var depth = 0;
  for (var i = start; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);
    if (code == openBraceCode) {
      depth += 1;
      continue;
    }
    if (code == closeBraceCode) {
      depth -= 1;
      if (depth == 0) return i;
    }
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
      continue;
    }
    if (code == 92) {
      escaped = true;
      continue;
    }
    if (code == 40) {
      depth += 1;
      continue;
    }
    if (code == 41) {
      depth -= 1;
      if (depth == 0) return i;
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
      continue;
    }
    if (code == 92) {
      escaped = true;
      continue;
    }
    if (code != 40) continue;
    if (i + 1 < body.length && body.codeUnitAt(i + 1) == questionCode) {
      continue;
    }
    count += 1;
  }
  return count;
}
