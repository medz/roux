// Data models for roux route matching.
// ignore_for_file: public_member_api_docs

// ── character constants ────────────────────────────────────────────────────

const int colonCode = 58,
    asteriskCode = 42,
    openBraceCode = 123,
    closeBraceCode = 125,
    questionCode = 63,
    plusCode = 43;

// ── specificity and bucket constants ──────────────────────────────────────

const int specRem = 0, specDyn = 1, specStruct = 2, specExact = 3;
const int bucketHigh = 0, bucketRepeat = 1, bucketLate = 2, bucketDeferred = 3;

// ── error prefixes ─────────────────────────────────────────────────────────

const String dupShape = 'Duplicate route shape conflicts with existing route: ';
const String dupWildcard =
    'Duplicate wildcard route shape at prefix for pattern: ';
const String dupFallback = 'Duplicate global fallback route: ';
const String emptySegment = 'Route pattern contains empty segment: ';

// ── public types ───────────────────────────────────────────────────────────

/// Controls how duplicate route registrations are handled.
enum DuplicatePolicy { reject, replace, keepFirst, append }

/// Result of a successful route match.
class RouteMatch<T> {
  final T data;
  final Map<String, String>? params;
  RouteMatch(this.data, [this.params]);
}

/// Stored route with capture metadata, specificity rank, and append chain.
class RouteEntry<T> {
  final T data;
  final List<String> names;
  final String? catchAllName; // '_' = unnamed **
  final int rank;
  final int order;
  RouteEntry<T>? next;
  late final RouteMatch<T> plainMatch = RouteMatch(data);

  RouteEntry(
    this.data,
    this.names,
    this.catchAllName,
    int specificity,
    int depth,
    int staticChars,
    int constraintScore,
    this.order,
  ) : rank =
          (((specificity * 256) + depth) * 4096 + staticChars) * 4 +
          constraintScore {
    _validateNames();
  }

  void _validateNames() {
    final seen = <String>{};
    for (final n in names) {
      if (!seen.add(n)) {
        throw FormatException('Duplicate capture name in route: $n');
      }
    }
    if (catchAllName != null && catchAllName != '_') {
      if (!seen.add(catchAllName!)) {
        throw FormatException('Duplicate capture name in route: $catchAllName');
      }
    }
  }

  RouteEntry<T> appended(RouteEntry<T> entry) {
    var cur = this;
    while (cur.next != null) {
      cur = cur.next!;
    }
    cur.next = entry;
    return this;
  }

  RouteMatch<T> materialize(List<String> captures, {String? remainder}) {
    if (names.isEmpty && catchAllName == null) return plainMatch;
    final params = <String, String>{};
    for (var i = 0; i < names.length; i++) {
      params[names[i]] = captures[i];
    }
    if (catchAllName != null && catchAllName != '_') {
      params[catchAllName!] = remainder ?? '';
    }
    return RouteMatch(data, params);
  }
}

/// Per-path method slot storing ANY and method-specific route entries.
class MethodSlot<T> {
  RouteEntry<T>? any;
  Map<String, RouteEntry<T>>? _methods;

  void add(
    String? method,
    RouteEntry<T> entry,
    DuplicatePolicy policy,
    String pattern,
    String dupPrefix,
  ) {
    if (method == null) {
      any = _merge(any, entry, policy, pattern, dupPrefix);
    } else {
      (_methods ??= {})[method] = _merge(
        _methods![method],
        entry,
        policy,
        pattern,
        dupPrefix,
      );
    }
  }

  RouteEntry<T>? lookup(String? method) =>
      method == null ? any : (_methods?[method] ?? any);

  void collect(
    String? method,
    void Function(RouteEntry<T>, int methodRank) emit,
  ) {
    if (any != null) emit(any!, 0);
    if (method != null) {
      final e = _methods?[method];
      if (e != null) emit(e, 1);
    }
  }
}

RouteEntry<T> _merge<T>(
  RouteEntry<T>? existing,
  RouteEntry<T> replacement,
  DuplicatePolicy policy,
  String pattern,
  String dupPrefix,
) {
  if (existing == null) return replacement;
  final a = existing.names, b = replacement.names;
  if (a.length != b.length ||
      existing.catchAllName != replacement.catchAllName) {
    throw FormatException('$dupShape$pattern');
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw FormatException('$dupShape$pattern');
  }
  return switch (policy) {
    DuplicatePolicy.reject => throw FormatException('$dupPrefix$pattern'),
    DuplicatePolicy.replace => replacement,
    DuplicatePolicy.keepFirst => existing,
    DuplicatePolicy.append => existing.appended(replacement),
  };
}

// ── param name helpers ─────────────────────────────────────────────────────

bool isParamCode(int code, bool first) =>
    ((code | 32) >= 97 && (code | 32) <= 122) ||
    code == 95 ||
    (!first && code >= 48 && code <= 57);

bool validParamSlice(String s, int start, int end) {
  if (start >= end) return false;
  for (var i = start; i < end; i++) {
    if (!isParamCode(s.codeUnitAt(i), i == start)) return false;
  }
  return true;
}

/// Reads a `**` or `**:name` wildcard name. Returns '_' for unnamed.
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

// ── matchAll accumulator ───────────────────────────────────────────────────

class MatchAccumulator<T> {
  final _items = <(RouteMatch<T>, int, int, int)>[];

  void add(RouteMatch<T> match, int rank, int methodRank, int order) =>
      _items.add((match, rank, methodRank, order));

  List<RouteMatch<T>> get results {
    _items.sort((a, b) {
      final r = a.$2 - b.$2;
      if (r != 0) return r;
      final m = a.$3 - b.$3;
      if (m != 0) return m;
      return a.$4 - b.$4;
    });
    return [for (final item in _items) item.$1];
  }
}
