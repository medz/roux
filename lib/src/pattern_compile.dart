part of 'router.dart';

bool _isValidParamName(String name) {
  if (name.isEmpty) return false;
  var code = name.codeUnitAt(0);
  if (!(((code | 32) >= 97 && (code | 32) <= 122) || code == 95)) return false;
  for (var i = 1; i < name.length; i++) {
    code = name.codeUnitAt(i);
    if (!(((code | 32) >= 97 && (code | 32) <= 122) ||
        code == 95 ||
        (code >= 48 && code <= 57))) {
      return false;
    }
  }
  return true;
}

bool _hasValidParamNameSlice(String pattern, int start, int end) {
  if (start >= end) return false;
  for (var i = start; i < end; i++) {
    if (!_isParamNameCode(pattern.codeUnitAt(i), i == start)) return false;
  }
  return true;
}

_CompiledSlot<T>? _compilePatternRoute<T>(
  String pattern,
  T data,
  bool caseSensitive,
  int registrationOrder,
) {
  if (pattern.contains('{')) {
    return _compileGroupedRoute(
      pattern,
      data,
      caseSensitive,
      registrationOrder,
    );
  }
  var needsCompiled = false;
  var bucket = _compiledBucketHigh;
  var specificity = _singleDynamicSpecificity;
  var staticChars = 0;
  var constraintScore = 0;
  final regex = StringBuffer('^');
  final shape = StringBuffer('^');
  final paramNames = <String>[];
  final groupIndexes = <int>[];
  var groupCount = 0;
  var unnamedCount = 0;
  var cursor = pattern.length == 1 ? pattern.length : 1;
  while (cursor < pattern.length) {
    final segmentEnd = _findSegmentEnd(pattern, cursor);
    final firstCode = pattern.codeUnitAt(cursor);
    if (segmentEnd == cursor) {
      throw FormatException('$_emptySegment$pattern');
    }
    if (firstCode == _colonCode &&
        _hasValidParamNameSlice(pattern, cursor + 1, segmentEnd)) {
      regex.write('/([^/]+)');
      shape.write('/([^/]+)');
      paramNames.add(pattern.substring(cursor + 1, segmentEnd));
      groupCount += 1;
      groupIndexes.add(groupCount);
      cursor = segmentEnd + 1;
      continue;
    }
    if (segmentEnd - cursor == 1 && firstCode == _asteriskCode) {
      regex.write('/([^/]+)');
      shape.write('/([^/]+)');
      paramNames.add('${unnamedCount++}');
      groupCount += 1;
      groupIndexes.add(groupCount);
      needsCompiled = true;
      bucket = _compiledBucketLate;
      constraintScore = 1;
      cursor = segmentEnd + 1;
      continue;
    }
    final repeated = _readRepeatedParam(pattern, cursor, segmentEnd);
    if (repeated != null) {
      final quantifier = repeated.$2;
      if (quantifier == _plusCode) {
        regex.write('/(.+(?:/.+)*)');
        shape.write('/(.+(?:/.+)*)');
      } else {
        regex.write('(?:/(.*))?');
        shape.write('(?:/(.*))?');
      }
      paramNames.add(repeated.$1);
      groupCount += 1;
      groupIndexes.add(groupCount);
      needsCompiled = true;
      bucket = _compiledBucketRepeated;
      specificity = _remainderSpecificity;
      constraintScore = 1;
      cursor = segmentEnd + 1;
      continue;
    }
    final optionalName = _readOptionalParamName(pattern, cursor, segmentEnd);
    if (optionalName != null) {
      regex.write('(?:/([^/]+))?');
      shape.write('(?:/([^/]+))?');
      paramNames.add(optionalName);
      groupCount += 1;
      groupIndexes.add(groupCount);
      needsCompiled = true;
      bucket = _compiledBucketDeferred;
      specificity = _structuredDynamicSpecificity;
      constraintScore = 1;
      cursor = segmentEnd + 1;
      continue;
    }

    regex.write('/');
    shape.write('/');

    var segmentCursor = cursor;
    var lastWasParam = false;
    var segmentHasLiteral = false;
    var segmentCaptureCount = 0;
    while (segmentCursor < segmentEnd) {
      final code = pattern.codeUnitAt(segmentCursor);
      if (code == _asteriskCode) {
        regex.write('([^/]*)');
        shape.write('([^/]*)');
        paramNames.add('${unnamedCount++}');
        groupCount += 1;
        groupIndexes.add(groupCount);
        needsCompiled = true;
        constraintScore = constraintScore < 1 ? 1 : constraintScore;
        segmentCaptureCount += 1;
        if (segmentHasLiteral || segmentCaptureCount > 1) {
          specificity = _structuredDynamicSpecificity;
        }
        segmentCursor += 1;
        lastWasParam = false;
        continue;
      }
      if (code == _colonCode) {
        if (lastWasParam) {
          throw FormatException(
            'Unsupported segment syntax in route: $pattern',
          );
        }
        var nameEnd = segmentCursor + 1;
        while (nameEnd < segmentEnd &&
            _isParamNameCode(
              pattern.codeUnitAt(nameEnd),
              nameEnd == segmentCursor + 1,
            )) {
          nameEnd += 1;
        }
        final paramName = pattern.substring(segmentCursor + 1, nameEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        if (nameEnd < segmentEnd && pattern.codeUnitAt(nameEnd) == 40) {
          final regexEnd = _findRegexEnd(pattern, nameEnd, segmentEnd);
          final body = pattern.substring(nameEnd + 1, regexEnd);
          regex
            ..write('(')
            ..write(body)
            ..write(')');
          shape
            ..write('(')
            ..write(body)
            ..write(')');
          groupCount += 1;
          groupIndexes.add(groupCount);
          groupCount += _countCapturingGroups(body);
          constraintScore = constraintScore < 2 ? 2 : constraintScore;
          segmentCursor = regexEnd + 1;
        } else {
          regex.write('([^/]+)');
          shape.write('([^/]+)');
          groupCount += 1;
          groupIndexes.add(groupCount);
          segmentCursor = nameEnd;
        }
        paramNames.add(paramName);
        segmentCaptureCount += 1;
        if (segmentHasLiteral || segmentCaptureCount > 1) {
          specificity = _structuredDynamicSpecificity;
        }
        lastWasParam = true;
        needsCompiled = true;
        continue;
      }

      final literalStart = segmentCursor;
      segmentCursor += 1;
      while (segmentCursor < segmentEnd) {
        final literalCode = pattern.codeUnitAt(segmentCursor);
        if (literalCode == _colonCode || literalCode == _asteriskCode) break;
        segmentCursor += 1;
      }
      final literal = pattern.substring(literalStart, segmentCursor);
      staticChars += _literalCharCount(literal);
      regex.write(RegExp.escape(literal));
      shape.write(
        RegExp.escape(caseSensitive ? literal : literal.toLowerCase()),
      );
      segmentHasLiteral = true;
      if (segmentCaptureCount > 0) {
        specificity = _structuredDynamicSpecificity;
      }
      lastWasParam = false;
    }
    cursor = segmentEnd + 1;
  }
  regex.write(r'$');
  shape.write(r'$');
  if (!needsCompiled) return null;
  _validateCaptureNames(paramNames, null, pattern);
  return _CompiledSlot<T>(
    RegExp(regex.toString(), caseSensitive: caseSensitive),
    shape.toString(),
    bucket,
    groupIndexes,
    _Route<T>(
      data,
      paramNames,
      null,
      _pathDepth(pattern),
      specificity,
      staticChars,
      constraintScore,
      registrationOrder,
    ),
  );
}

_CompiledSlot<T> _compileGroupedRoute<T>(
  String pattern,
  T data,
  bool caseSensitive,
  int registrationOrder,
) {
  final regex = StringBuffer('^');
  final shape = StringBuffer('^');
  final paramNames = <String>[];
  final groupIndexes = <int>[];
  var groupCount = 0;
  var unnamedCount = 0;
  var staticChars = 0;
  var constraintScore = 1;

  void writeChunk(
    StringBuffer targetRegex,
    StringBuffer targetShape,
    int start,
    int end,
  ) {
    var cursor = start;
    while (cursor < end) {
      final code = pattern.codeUnitAt(cursor);
      if (code == _openBraceCode) {
        final close = _findGroupEnd(pattern, cursor + 1, end);
        final optional =
            close + 1 < end && pattern.codeUnitAt(close + 1) == _questionCode;
        final innerRegex = StringBuffer();
        final innerShape = StringBuffer();
        writeChunk(innerRegex, innerShape, cursor + 1, close);
        targetRegex
          ..write('(?:')
          ..write(innerRegex)
          ..write(optional ? ')?' : ')');
        targetShape
          ..write('(?:')
          ..write(innerShape)
          ..write(optional ? ')?' : ')');
        cursor = optional ? close + 2 : close + 1;
        continue;
      }
      if (code == _asteriskCode) {
        if (cursor + 1 < end &&
            pattern.codeUnitAt(cursor + 1) == _asteriskCode) {
          throw FormatException('Unsupported group syntax in route: $pattern');
        }
        targetRegex.write('([^/]*)');
        targetShape.write('([^/]*)');
        paramNames.add('${unnamedCount++}');
        groupCount += 1;
        groupIndexes.add(groupCount);
        constraintScore = 2;
        cursor += 1;
        continue;
      }
      if (code == _colonCode) {
        var nameEnd = cursor + 1;
        while (nameEnd < end &&
            _isParamNameCode(
              pattern.codeUnitAt(nameEnd),
              nameEnd == cursor + 1,
            )) {
          nameEnd += 1;
        }
        final paramName = pattern.substring(cursor + 1, nameEnd);
        if (!_isValidParamName(paramName)) {
          throw FormatException('Invalid parameter name in route: $pattern');
        }
        if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
          final regexEnd = _findRegexEnd(pattern, nameEnd, end);
          final body = pattern.substring(nameEnd + 1, regexEnd);
          targetRegex
            ..write('(')
            ..write(body)
            ..write(')');
          targetShape
            ..write('(')
            ..write(body)
            ..write(')');
          groupCount += 1;
          groupIndexes.add(groupCount);
          groupCount += _countCapturingGroups(body);
          constraintScore = constraintScore < 2 ? 2 : constraintScore;
          cursor = regexEnd + 1;
        } else {
          targetRegex.write('([^/]+)');
          targetShape.write('([^/]+)');
          groupCount += 1;
          groupIndexes.add(groupCount);
          cursor = nameEnd;
        }
        paramNames.add(paramName);
        continue;
      }
      if (code == _questionCode || code == _closeBraceCode) {
        throw FormatException('Unsupported group syntax in route: $pattern');
      }

      final literalStart = cursor;
      cursor += 1;
      while (cursor < end) {
        final literalCode = pattern.codeUnitAt(cursor);
        if (literalCode == _openBraceCode ||
            literalCode == _closeBraceCode ||
            literalCode == _questionCode ||
            literalCode == _colonCode ||
            literalCode == _asteriskCode) {
          break;
        }
        cursor += 1;
      }
      final literal = pattern.substring(literalStart, cursor);
      staticChars += _literalCharCount(literal);
      targetRegex.write(RegExp.escape(literal));
      targetShape.write(
        RegExp.escape(caseSensitive ? literal : literal.toLowerCase()),
      );
    }
  }

  writeChunk(regex, shape, 0, pattern.length);
  regex.write(r'$');
  shape.write(r'$');
  _validateCaptureNames(paramNames, null, pattern);
  return _CompiledSlot<T>(
    RegExp(regex.toString(), caseSensitive: caseSensitive),
    shape.toString(),
    _compiledBucketDeferred,
    groupIndexes,
    _Route<T>(
      data,
      paramNames,
      null,
      _pathDepth(pattern),
      _structuredDynamicSpecificity,
      staticChars,
      constraintScore,
      registrationOrder,
    ),
  );
}

void _validateCaptureNames(
  List<String> paramNames,
  String? wildcardName,
  String pattern,
) {
  final count = paramNames.length;
  if (count == 2) {
    if (paramNames[0] == paramNames[1]) {
      throw FormatException('Duplicate parameter name in route: $pattern');
    }
  } else if (count > 2) {
    for (var i = 0; i < count; i++) {
      final current = paramNames[i];
      for (var j = i + 1; j < count; j++) {
        if (current == paramNames[j]) {
          throw FormatException('Duplicate parameter name in route: $pattern');
        }
      }
    }
  }
  if (wildcardName == null) return;
  for (var i = 0; i < count; i++) {
    if (paramNames[i] == wildcardName) {
      throw FormatException('Duplicate parameter name in route: $pattern');
    }
  }
}

bool _isParamNameCode(int code, bool first) {
  if (first) {
    return ((code | 32) >= 97 && (code | 32) <= 122) || code == 95;
  }
  return ((code | 32) >= 97 && (code | 32) <= 122) ||
      code == 95 ||
      (code >= 48 && code <= 57);
}

String? _readOptionalParamName(String pattern, int start, int end) {
  if (start >= end || pattern.codeUnitAt(start) != _colonCode) return null;
  if (pattern.codeUnitAt(end - 1) != _questionCode) return null;
  final name = pattern.substring(start + 1, end - 1);
  return _isValidParamName(name) ? name : null;
}

const _questionCode = 63, _plusCode = 43;

(String, int)? _readRepeatedParam(String pattern, int start, int end) {
  if (start >= end || pattern.codeUnitAt(start) != _colonCode) return null;
  final last = pattern.codeUnitAt(end - 1);
  if (last != _asteriskCode && last != _plusCode) return null;
  final name = pattern.substring(start + 1, end - 1);
  if (!_isValidParamName(name)) return null;
  return (name, last);
}

int _findGroupEnd(String pattern, int start, int end) {
  var depth = 0;
  var cursor = start;
  while (cursor < end) {
    final code = pattern.codeUnitAt(cursor);
    if (code == _openBraceCode) {
      depth += 1;
      cursor += 1;
      continue;
    }
    if (code == _closeBraceCode) {
      if (depth == 0) return cursor;
      depth -= 1;
      cursor += 1;
      continue;
    }
    if (code == _colonCode) {
      var nameEnd = cursor + 1;
      while (nameEnd < end &&
          _isParamNameCode(
            pattern.codeUnitAt(nameEnd),
            nameEnd == cursor + 1,
          )) {
        nameEnd += 1;
      }
      if (nameEnd < end && pattern.codeUnitAt(nameEnd) == 40) {
        cursor = _findRegexEnd(pattern, nameEnd, end) + 1;
        continue;
      }
    }
    cursor += 1;
  }
  throw FormatException('Unclosed group in route: $pattern');
}

int _findRegexEnd(String pattern, int start, int segmentEnd) {
  var depth = 0;
  var escaped = false;
  var inCharClass = false;
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
    if (inCharClass) {
      if (code == 93) inCharClass = false;
      continue;
    }
    if (code == 91) {
      inCharClass = true;
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
  throw FormatException('Unterminated regex in route: $pattern');
}

int _countCapturingGroups(String pattern) {
  var count = 0;
  var escaped = false;
  var inCharClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final code = pattern.codeUnitAt(i);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (code == 92) {
      escaped = true;
      continue;
    }
    if (inCharClass) {
      if (code == 93) inCharClass = false;
      continue;
    }
    if (code == 91) {
      inCharClass = true;
      continue;
    }
    if (code != 40) continue;
    if (i + 1 >= pattern.length || pattern.codeUnitAt(i + 1) != 63) {
      count += 1;
      continue;
    }
    if (i + 2 < pattern.length && pattern.codeUnitAt(i + 2) == 60) {
      if (i + 3 < pattern.length) {
        final next = pattern.codeUnitAt(i + 3);
        if (next != 61 && next != 33) count += 1;
      }
    }
  }
  return count;
}
