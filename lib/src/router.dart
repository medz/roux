import 'dart:collection';

part 'input_path.dart';
part 'pattern_compile.dart';
part 'pattern_match.dart';
part 'simple_engine.dart';
part 'specificity.dart';

const _slashCode = 47,
    _asteriskCode = 42,
    _colonCode = 58,
    _openBraceCode = 123,
    _closeBraceCode = 125,
    _mapAt = 4;
const _remainderSpecificity = 0,
    _singleDynamicSpecificity = 1,
    _structuredDynamicSpecificity = 2,
    _exactSpecificity = 3;
const _compiledBucketHigh = 0,
    _compiledBucketRepeated = 1,
    _compiledBucketLate = 2,
    _compiledBucketDeferred = 3;
const _dupShape = 'Duplicate route shape conflicts with existing route: ';
const _dupWildcard = 'Duplicate wildcard route shape at prefix for pattern: ';
const _dupFallback = 'Duplicate global fallback route: ';
const _emptySegment = 'Route pattern contains empty segment: ';

/// Controls how duplicate route registrations are handled.
enum DuplicatePolicy {
  /// Throws when the same normalized route shape is registered again.
  reject,

  /// Replaces the existing route entry with the latest registration.
  replace,

  /// Keeps the first registered route entry and ignores later duplicates.
  keepFirst,

  /// Retains every duplicate route entry in registration order.
  append,
}

/// The matched route payload and any captured path parameters.
class RouteMatch<T> {
  /// The value associated with the matched route.
  final T data;

  /// Captured parameter values for the matched route, if any.
  final Map<String, String>? params;

  /// Creates an eager route match with an optional prebuilt params map.
  RouteMatch(this.data, [this.params]);
}

/// A compact path router with support for exact, parameter, and wildcard routes.
class Router<T> {
  final _RouteSet<T> _anyRoutes = _RouteSet<T>();
  Map<String, _RouteSet<T>>? _routeSetsByMethod;
  final DuplicatePolicy _duplicatePolicy;
  final bool _caseSensitive;
  final bool _decodePath;
  final bool _normalizePath;
  int _nextRegistrationOrder = 0;

  /// Creates a router and optionally preloads [routes].
  Router({
    Map<String, T>? routes,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.reject,
    bool caseSensitive = true,
    bool decodePath = false,
    bool normalizePath = false,
  }) : _duplicatePolicy = duplicatePolicy,
       _caseSensitive = caseSensitive,
       _decodePath = decodePath,
       _normalizePath = normalizePath {
    if (routes != null && routes.isNotEmpty) addAll(routes);
  }

  /// Registers a route payload for [path].
  void add(
    String path,
    T data, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) => _addPattern(
    _routeSetForWrite(method),
    path,
    data,
    duplicatePolicy: duplicatePolicy ?? _duplicatePolicy,
  );

  /// Registers every entry in [routes].
  void addAll(
    Map<String, T> routes, {
    String? method,
    DuplicatePolicy? duplicatePolicy,
  }) {
    final routeSet = _routeSetForWrite(method),
        policy = duplicatePolicy ?? _duplicatePolicy;
    for (final entry in routes.entries) {
      _addPattern(routeSet, entry.key, entry.value, duplicatePolicy: policy);
    }
  }

  /// Returns the highest-priority match for [path], or `null` if none exists.
  RouteMatch<T>? match(String path, {String? method}) {
    final normalized = _prepareInputPath(path);
    if (normalized == null) return null;
    final methodToken = method == null ? null : _methodToken(method);
    final routeSet = methodToken == null
        ? null
        : _routeSetsByMethod?[methodToken];
    return (routeSet == null ? null : _matchInRouteSet(routeSet, normalized)) ??
        _matchInRouteSet(_anyRoutes, normalized);
  }

  /// Returns every matching route for [path] in router priority order.
  List<RouteMatch<T>> matchAll(String path, {String? method}) {
    final normalized = _prepareInputPath(path);
    if (normalized == null) return <RouteMatch<T>>[];
    final pathDepth = _pathDepth(normalized);
    final methodToken = method == null ? null : _methodToken(method);
    final routeSet = methodToken == null
        ? null
        : _routeSetsByMethod?[methodToken];
    final collected = _MatchCollector<T>(
      routeSet != null ||
          _needsSpecificitySort(_anyRoutes) ||
          (routeSet != null && _needsSpecificitySort(routeSet)),
    );
    _collectRouteSet(_anyRoutes, normalized, pathDepth, 0, collected);
    if (routeSet != null) {
      _collectRouteSet(routeSet, normalized, pathDepth, 1, collected);
    }
    return collected.finish();
  }

  _RouteSet<T> _routeSetForWrite(String? method) => method == null
      ? _anyRoutes
      : (_routeSetsByMethod ??= <String, _RouteSet<T>>{}).putIfAbsent(
          _methodToken(method),
          _RouteSet<T>.new,
        );

  _Route<T> _newRoute(
    T data,
    List<String> paramNames,
    String? wildcardName,
    String pattern,
    int depth,
    int specificity,
    int staticChars,
    int constraintScore,
  ) {
    _validateCaptureNames(paramNames, wildcardName, pattern);
    return _Route<T>(
      data,
      paramNames,
      wildcardName,
      depth,
      specificity,
      staticChars,
      constraintScore,
      _nextRegistrationOrder++,
    );
  }

  bool _needsSpecificitySort(_RouteSet<T> routeSet) =>
      routeSet.hasBranchingChoices ||
      routeSet.root.paramChild != null ||
      routeSet.repeatedCompiledRoutes != null ||
      routeSet.compiledRoutes != null ||
      routeSet.lateCompiledRoutes != null ||
      routeSet.deferredCompiledRoutes != null;

  String _methodToken(String method) {
    final token = method.trim();
    if (token.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Method must not be empty.');
    }
    return token.toUpperCase();
  }

  String _canonicalPath(String path) =>
      _caseSensitive ? path : path.toLowerCase();

  String _canonicalLiteral(String literal) =>
      _caseSensitive ? literal : literal.toLowerCase();

  String? _prepareInputPath(String path) {
    if (_decodePath && path.contains('%')) {
      try {
        path = Uri.decodeFull(path);
      } on ArgumentError {
        return null;
      }
    }
    return _normalizePath
        ? _normalizePathInput(path)
        : _normalizeInputPath(path);
  }

  RouteMatch<T>? _matchInRouteSet(_RouteSet<T> routeSet, String normalized) {
    final exact =
        routeSet.staticExactRoutes[_canonicalPath(normalized)]?.noParamsMatch;
    if (exact != null) return exact;
    if (!routeSet.hasSlowMatchPath) {
      return routeSet.hasBranchingChoices
          ? _matchNodePathFast(routeSet, normalized)
          : _matchNodePathStraight(routeSet, normalized);
    }
    final fallback = routeSet.globalFallback,
        compiled = routeSet.compiledRoutes,
        repeated = routeSet.repeatedCompiledRoutes,
        late = routeSet.lateCompiledRoutes,
        deferred = routeSet.deferredCompiledRoutes;
    return (compiled == null ? null : _matchCompiled(compiled, normalized)) ??
        _matchNodePath(routeSet, normalized, false) ??
        (late == null ? null : _matchCompiled(late, normalized)) ??
        (repeated == null ? null : _matchCompiled(repeated, normalized)) ??
        _matchNodePath(routeSet, normalized, true) ??
        (deferred == null ? null : _matchCompiled(deferred, normalized)) ??
        (fallback == null ? null : _materialize(fallback, normalized, null, 1));
  }

  void _collectRouteSet(
    _RouteSet<T> routeSet,
    String normalized,
    int pathDepth,
    int methodRank,
    _MatchCollector<T> output,
  ) {
    final fallback = routeSet.globalFallback;
    if (fallback != null) {
      _collectSlot(fallback, normalized, null, 1, methodRank, output);
    }
    final repeated = routeSet.repeatedCompiledRoutes;
    if (repeated != null) {
      _collectCompiled(repeated, normalized, methodRank, output);
    }
    _collectNode(routeSet, normalized, methodRank, output);
    final compiled = routeSet.compiledRoutes;
    if (compiled != null) {
      _collectCompiled(compiled, normalized, methodRank, output);
    }
    final late = routeSet.lateCompiledRoutes;
    if (late != null) {
      _collectCompiled(late, normalized, methodRank, output);
    }
    final exactStatic = routeSet.staticExactRoutes[_canonicalPath(normalized)];
    if (exactStatic != null) {
      _collectSlot(exactStatic, normalized, null, 0, methodRank, output);
    }
    final deferred = routeSet.deferredCompiledRoutes;
    if (deferred != null) {
      _collectCompiled(deferred, normalized, methodRank, output);
    }
  }

  _Route<T> _mergedRoute(
    _Route<T>? existing,
    _Route<T> route,
    String pattern,
    DuplicatePolicy duplicatePolicy,
    String rejectPrefix,
  ) => existing == null
      ? route
      : _resolveDup(existing, route, pattern, duplicatePolicy, rejectPrefix);

  _Route<T> _resolveDup(
    _Route<T> existing,
    _Route<T> replacement,
    String pattern,
    DuplicatePolicy duplicatePolicy,
    String rejectPrefix,
  ) {
    final a = existing.paramNames, b = replacement.paramNames;
    if (a.length != b.length) throw FormatException('$_dupShape$pattern');
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) throw FormatException('$_dupShape$pattern');
    }
    if (existing.wildcardName != replacement.wildcardName) {
      throw FormatException('$_dupShape$pattern');
    }
    return switch (duplicatePolicy) {
      DuplicatePolicy.reject => throw FormatException('$rejectPrefix$pattern'),
      DuplicatePolicy.replace => replacement,
      DuplicatePolicy.keepFirst => existing,
      DuplicatePolicy.append => existing.appended(replacement),
    };
  }

  void _addCompiledPattern(
    _RouteSet<T> routeSet,
    String normalized,
    T data,
    DuplicatePolicy duplicatePolicy,
  ) {
    final compiled = _compilePatternRoute(
      normalized,
      data,
      _caseSensitive,
      _nextRegistrationOrder++,
    );
    if (compiled == null) {
      throw FormatException('Unsupported segment syntax in route: $normalized');
    }
    routeSet.hasSlowMatchPath = true;
    _addCompiled(this, routeSet, compiled, normalized, duplicatePolicy);
    if (compiled.route.paramNames.length > routeSet.maxParamDepth) {
      routeSet.maxParamDepth = compiled.route.paramNames.length;
    }
  }
}

class _RouteSet<T> {
  final _Node<T> root = _Node<T>();
  bool hasSlowMatchPath = false;
  bool hasBranchingChoices = false;
  _Route<T>? globalFallback;
  _CompiledSlot<T>? compiledRoutes;
  _CompiledSlot<T>? repeatedCompiledRoutes;
  _CompiledSlot<T>? lateCompiledRoutes;
  _CompiledSlot<T>? deferredCompiledRoutes;
  final Map<String, _Route<T>> staticExactRoutes = <String, _Route<T>>{};
  int maxParamDepth = 0;
}

class _Route<T> {
  final T data;
  final List<String> paramNames;
  final String? wildcardName;
  final int depth;
  final int specificity;
  final int staticChars;
  final int constraintScore;
  final int registrationOrder;
  final int rankPrefix;
  _Route<T>? next;
  late final RouteMatch<T> noParamsMatch = RouteMatch<T>(data);
  _Route(
    this.data,
    this.paramNames,
    this.wildcardName,
    this.depth,
    this.specificity,
    this.staticChars,
    this.constraintScore,
    this.registrationOrder,
  ) : rankPrefix =
          (((specificity * 256) + depth) * 4096 + staticChars) * 4 +
          constraintScore;
  _Route<T> appended(_Route<T> route) {
    var current = this;
    while (current.next != null) {
      current = current.next!;
    }
    current.next = route;
    return this;
  }
}
