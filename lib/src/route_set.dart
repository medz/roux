import 'route_model.dart';
import 'route_path.dart';
import 'pattern_engine.dart';
import 'trie_engine.dart';

/// Groups trie and pattern routing for one method bucket.
class RouteSet<T> {
  /// Creates a route set using a shared case-sensitivity policy.
  RouteSet(bool caseSensitive)
    : trie = TrieEngine(caseSensitive),
      patterns = PatternEngine(caseSensitive);

  /// Internal match-mode value for mixed simple and pattern routes.
  static const int hybridMode = 0, simpleMode = 1, straightMode = 2;

  /// Trie-backed matcher for exact and segment-level routes.
  final TrieEngine<T> trie;

  /// Compiled matcher for richer pathname syntax.
  final PatternEngine<T> patterns;
  int _matchMode = straightMode;

  /// Whether collected matches require final specificity sorting.
  bool get needsSort =>
      trie.hasBranches || trie.hasRootParamChild || patterns.hasRoutes;

  /// Whether this route set requires strict path validation.
  bool get needsStrict => trie.needsStrict || patterns.hasRoutes;

  /// Whether normalized lookups can stay on the straight fast path.
  bool get canNormBest =>
      !patterns.hasRoutes &&
      trie.globalFallback == null &&
      trie.canMatchStraightNormalized;

  /// Whether normalized lookups can skip directly to exact matching.
  bool get canNormExact =>
      !patterns.hasRoutes && trie.exactRoutes.isNotEmpty && !trie.hasNonExact;

  /// Registers a route into either the trie or compiled matcher.
  void addRoute(
    String patternPath,
    T data,
    DuplicatePolicy duplicatePolicy,
    int order,
  ) {
    if (!patternPath.startsWith('/')) {
      throw FormatException('Route pattern must start with "/": $patternPath');
    }
    final normalized = trimTrailingSlash(patternPath);
    if (!trie.add(normalized, data, duplicatePolicy, order)) {
      patterns.add(normalized, data, duplicatePolicy, order);
    }
    _refreshMatchMode();
  }

  /// Returns the best match for an already prepared path.
  @pragma('vm:prefer-inline')
  RouteMatch<T>? matchBest(String normalized) {
    switch (_matchMode) {
      case straightMode:
        return trie.matchStraight(normalized);
      case simpleMode:
        final exact = trie.matchExact(normalized);
        if (exact != null) return exact;
        return trie.match(normalized, true);
    }
    final exact = trie.matchExact(normalized);
    if (exact != null) return exact;
    return patterns.matchBucket(bucketHigh, normalized) ??
        trie.match(normalized, false) ??
        patterns.matchBucket(bucketLate, normalized) ??
        patterns.matchBucket(bucketRepeat, normalized) ??
        trie.match(normalized, true) ??
        patterns.matchBucket(bucketDeferred, normalized) ??
        (trie.globalFallback == null
            ? null
            : trie.materialize(trie.globalFallback!, normalized, null, 1));
  }

  /// Returns the best match for a raw path under normalizePath=true.
  @pragma('vm:prefer-inline')
  RouteMatch<T>? matchBestNormalized(String path) {
    if (canNormBest) {
      final straight = trie.matchStraightNormalized(path);
      if (straight != null || trie.exactRoutes.isEmpty) return straight;
    } else if (!canNormExact) {
      return trie.matchStraightNormalized(path);
    }
    final normalized = normalizeRoutePath(path);
    return normalized == null ? null : trie.exactRoutes[normalized]?.plainMatch;
  }

  /// Collects all matches for [normalized] into [output].
  @pragma('vm:prefer-inline')
  void collectMatches(
    String normalized,
    int methodRank,
    MatchAccumulator<T> output,
  ) {
    final fallback = trie.globalFallback;
    if (fallback != null) {
      trie.collectSlot(fallback, normalized, null, 1, methodRank, output);
    }
    patterns.collectBucket(bucketRepeat, normalized, methodRank, output);
    trie.collect(normalized, methodRank, output);
    patterns.collectBucket(bucketHigh, normalized, methodRank, output);
    patterns.collectBucket(bucketLate, normalized, methodRank, output);
    if (trie.exactRoutes.isNotEmpty) {
      final exact =
          trie.exactRoutes[trie.caseSensitive
              ? normalized
              : normalized.toLowerCase()];
      if (exact != null) {
        trie.collectSlot(exact, normalized, null, 0, methodRank, output);
      }
    }
    patterns.collectBucket(bucketDeferred, normalized, methodRank, output);
  }

  void _refreshMatchMode() {
    _matchMode = patterns.hasRoutes || trie.globalFallback != null
        ? hybridMode
        : trie.exactRoutes.isEmpty && !trie.hasBranches
        ? straightMode
        : simpleMode;
  }
}
