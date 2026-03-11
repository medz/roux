/// Shared character-code constants used by route parsing.
const int slashCode = 47,
    asteriskCode = 42,
    colonCode = 58,
    openBraceCode = 123,
    closeBraceCode = 125,
    questionCode = 63,
    plusCode = 43,
    mapAt = 4;

/// Specificity levels used to sort route matches.
const int specRem = 0, specDyn = 1, specStruct = 2, specExact = 3;

/// Pattern buckets ordered by matching precedence.
const int bucketHigh = 0, bucketRepeat = 1, bucketLate = 2, bucketDeferred = 3;

/// Duplicate-route error prefixes used during registration.
const String dupShape = 'Duplicate route shape conflicts with existing route: ';

/// Prefix used when a wildcard route conflicts with an existing shape.
const String dupWildcard =
    'Duplicate wildcard route shape at prefix for pattern: ';

/// Prefix used when the global fallback route is duplicated.
const String dupFallback = 'Duplicate global fallback route: ';

/// Error text used when a pattern contains `//`.
const String emptySegment = 'Route pattern contains empty segment: ';

/// Controls how duplicate route registrations are handled.
enum DuplicatePolicy {
  /// Reject duplicate registrations.
  reject,

  /// Replace the existing route.
  replace,

  /// Keep the first registered route.
  keepFirst,

  /// Append duplicate routes into a chain.
  append,
}

/// Public route match result.
class RouteMatch<T> {
  /// The matched route payload.
  final T data;

  /// Captured route parameters, when present.
  final Map<String, String>? params;

  /// Creates a route match.
  RouteMatch(this.data, [this.params]);
}

/// Stored route metadata and append chain for duplicate policies.
class RouteEntry<T> {
  /// The route payload.
  final T data;

  /// Ordered parameter names captured by this route.
  final List<String> names;

  /// Optional wildcard capture name.
  final String? wildcard;

  /// Registration order used as the final sort tie-breaker.
  final int order;

  /// Packed specificity sort key.
  final int rank;

  /// The next appended route in a duplicate-policy chain.
  RouteEntry<T>? next;

  /// Cached no-params match result.
  late final plainMatch = RouteMatch(data);

  /// Creates route metadata for matching and sorting.
  RouteEntry(
    this.data,
    this.names,
    this.wildcard,
    String pattern,
    int depth,
    int specificity,
    int staticChars,
    int constraintScore,
    this.order,
  ) : rank =
          (((specificity * 256) + depth) * 4096 + staticChars) * 4 +
          constraintScore {
    if (names.isEmpty && (wildcard == null || wildcard == '_')) return;
    if (names.length == 1 &&
        (wildcard == null || wildcard == '_' || wildcard != names[0])) {
      return;
    }
    final seen = {...names};
    if (seen.length != names.length ||
        (wildcard != null && wildcard != '_' && !seen.add(wildcard!))) {
      throw FormatException('Duplicate capture name in route: $pattern');
    }
  }

  /// Appends another route to this duplicate-policy chain.
  RouteEntry<T> appended(RouteEntry<T> route) {
    var current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}

/// Collects raw matches and applies final ordering when requested.
class MatchAccumulator<T> {
  /// Whether matches should be sorted by specificity before returning.
  final bool sortBySpecificity;

  /// Collected match, route, and method-rank tuples.
  final items = <(RouteMatch<T>, RouteEntry<T>, int)>[];

  /// Creates an accumulator.
  MatchAccumulator(this.sortBySpecificity);

  /// Adds a collected match item.
  @pragma('vm:prefer-inline')
  void add(RouteMatch<T> match, RouteEntry<T> route, int methodRank) =>
      items.add((match, route, methodRank));

  /// Returns the finalized ordered match list.
  @pragma('vm:prefer-inline')
  List<RouteMatch<T>> get matches {
    if (sortBySpecificity) {
      if (items.length < 8) {
        for (var i = 1; i < items.length; i++) {
          final item = items[i];
          var j = i - 1;
          while (j >= 0 && _compareMatchItem(items[j], item) > 0) {
            items[j + 1] = items[j];
            j -= 1;
          }
          items[j + 1] = item;
        }
      } else {
        items.sort(_compareMatchItem);
      }
    }
    return [for (final item in items) item.$1];
  }
}

@pragma('vm:prefer-inline')
int _compareMatchItem<T>(
  (RouteMatch<T>, RouteEntry<T>, int) a,
  (RouteMatch<T>, RouteEntry<T>, int) b,
) {
  final rankDiff = a.$2.rank - b.$2.rank;
  if (rankDiff != 0) return rankDiff;
  final methodDiff = a.$3 - b.$3;
  if (methodDiff != 0) return methodDiff;
  return a.$2.order - b.$2.order;
}

/// Merges a route according to the duplicate policy for one route shape.
RouteEntry<T> mergeRouteEntries<T>(
  RouteEntry<T>? existing,
  RouteEntry<T> replacement,
  String pattern,
  DuplicatePolicy duplicatePolicy,
  String rejectPrefix,
) {
  if (existing == null) return replacement;
  final a = existing.names;
  final b = replacement.names;
  if (a.length != b.length || existing.wildcard != replacement.wildcard) {
    throw FormatException('$dupShape$pattern');
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw FormatException('$dupShape$pattern');
  }
  return switch (duplicatePolicy) {
    DuplicatePolicy.reject => throw FormatException('$rejectPrefix$pattern'),
    DuplicatePolicy.replace => replacement,
    DuplicatePolicy.keepFirst => existing,
    DuplicatePolicy.append => existing.appended(replacement),
  };
}

/// Validates a parameter-name slice inside a larger pattern string.
bool validParamSlice(String pattern, int start, int end) {
  if (start >= end) return false;
  for (var i = start; i < end; i++) {
    if (!isParamCode(pattern.codeUnitAt(i), i == start)) return false;
  }
  return true;
}

/// Returns whether a code point is valid for a parameter identifier.
bool isParamCode(int code, bool first) =>
    ((code | 32) >= 97 && (code | 32) <= 122) ||
    code == 95 ||
    (!first && code >= 48 && code <= 57);

/// Reads a `**` remainder wildcard name, if present.
String? readRestName(String pattern, int start, int end) {
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
  return validParamSlice(name, 0, name.length) ? name : null;
}
