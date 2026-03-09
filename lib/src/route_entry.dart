import 'types.dart';

const int slashCode = 47,
    asteriskCode = 42,
    colonCode = 58,
    openBraceCode = 123,
    closeBraceCode = 125,
    questionCode = 63,
    plusCode = 43,
    mapAt = 4;

const int remainderSpecificity = 0,
    singleDynamicSpecificity = 1,
    structuredDynamicSpecificity = 2,
    exactSpecificity = 3;

const int compiledBucketHigh = 0,
    compiledBucketRepeated = 1,
    compiledBucketLate = 2,
    compiledBucketDeferred = 3;

const String dupShape = 'Duplicate route shape conflicts with existing route: ';
const String dupWildcard =
    'Duplicate wildcard route shape at prefix for pattern: ';
const String dupFallback = 'Duplicate global fallback route: ';
const String emptySegment = 'Route pattern contains empty segment: ';

class RouteEntry<T> {
  final T data;
  final List<String> paramNames;
  final String? wildcardName;
  final int registrationOrder;
  final int rankPrefix;
  RouteEntry<T>? next;
  late final RouteMatch<T> noParamsMatch = RouteMatch<T>(data);

  RouteEntry(
    this.data,
    this.paramNames,
    this.wildcardName,
    int depth,
    int specificity,
    int staticChars,
    int constraintScore,
    this.registrationOrder,
  ) : rankPrefix =
          (((specificity * 256) + depth) * 4096 + staticChars) * 4 +
          constraintScore;

  RouteEntry<T> appended(RouteEntry<T> route) {
    var current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}

RouteEntry<T> mergeRouteEntries<T>(
  RouteEntry<T>? existing,
  RouteEntry<T> replacement,
  String pattern,
  DuplicatePolicy duplicatePolicy,
  String rejectPrefix,
) {
  if (existing == null) return replacement;
  final a = existing.paramNames;
  final b = replacement.paramNames;
  if (a.length != b.length) throw FormatException('$dupShape$pattern');
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw FormatException('$dupShape$pattern');
  }
  if (existing.wildcardName != replacement.wildcardName) {
    throw FormatException('$dupShape$pattern');
  }
  return switch (duplicatePolicy) {
    DuplicatePolicy.reject => throw FormatException('$rejectPrefix$pattern'),
    DuplicatePolicy.replace => replacement,
    DuplicatePolicy.keepFirst => existing,
    DuplicatePolicy.append => existing.appended(replacement),
  };
}

void validateCaptureNames(
  List<String> paramNames,
  String? wildcardName,
  String pattern,
) {
  if (paramNames.isEmpty) return;
  final seen = <String>{};
  for (final name in paramNames) {
    if (!seen.add(name)) {
      throw FormatException('Duplicate capture name in route: $pattern');
    }
  }
  if (wildcardName != null && wildcardName != '_' && !seen.add(wildcardName)) {
    throw FormatException('Duplicate capture name in route: $pattern');
  }
}

bool isValidParamName(String name) {
  if (name.isEmpty) return false;
  var code = name.codeUnitAt(0);
  if (!(((code | 32) >= 97 && (code | 32) <= 122) || code == 95)) {
    return false;
  }
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

bool hasValidParamNameSlice(String pattern, int start, int end) {
  if (start >= end) return false;
  for (var i = start; i < end; i++) {
    if (!isParamNameCode(pattern.codeUnitAt(i), i == start)) return false;
  }
  return true;
}

bool isParamNameCode(int code, bool first) =>
    ((code | 32) >= 97 && (code | 32) <= 122) ||
    code == 95 ||
    (!first && code >= 48 && code <= 57);

String? readDoubleWildcardName(String pattern, int start, int end) {
  if (end - start == 2 &&
      pattern.codeUnitAt(start) == asteriskCode &&
      pattern.codeUnitAt(start + 1) == asteriskCode) {
    return '_';
  }
  if (end - start <= 3 ||
      pattern.codeUnitAt(start) != asteriskCode ||
      pattern.codeUnitAt(start + 1) != asteriskCode ||
      pattern.codeUnitAt(start + 2) != colonCode) {
    return null;
  }
  final name = pattern.substring(start + 3, end);
  return isValidParamName(name) ? name : null;
}
