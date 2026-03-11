import 'route_set.dart';

/// Stores per-method route sets for the experimental router.
class MethodTable<T> {
  /// Shared slots for common HTTP methods.
  final commonRoutes = List<RouteSet<T>?>.filled(7, null);

  /// Additional method buckets keyed by canonicalized method name.
  final extraRoutes = <String, RouteSet<T>>{};

  /// Returns the writable route set for [method], creating it on demand.
  @pragma('vm:prefer-inline')
  RouteSet<T> forWriteMethod(String method, bool caseSensitive) {
    final normalized = canonicalizeMethod(method);
    final commonIndex = commonMethodIndex(normalized);
    return commonIndex >= 0
        ? commonRoutes[commonIndex] ??= RouteSet(caseSensitive)
        : extraRoutes.putIfAbsent(normalized, () => RouteSet(caseSensitive));
  }

  /// Looks up the route set for [method], if one exists.
  @pragma('vm:prefer-inline')
  RouteSet<T>? lookupMethod(String method) {
    final normalized = canonicalizeMethod(method),
        commonIndex = commonMethodIndex(normalized);
    return commonIndex >= 0
        ? commonRoutes[commonIndex]
        : extraRoutes[normalized];
  }
}

/// Maps a canonical method name to its common-slot index.
@pragma('vm:prefer-inline')
int commonMethodIndex(String method) {
  return switch (method) {
    'GET' => 0,
    'POST' => 1,
    'PUT' => 2,
    'PATCH' => 3,
    'DELETE' => 4,
    'HEAD' => 5,
    'OPTIONS' => 6,
    _ => -1,
  };
}

/// Trims and uppercases a method name for table lookups.
@pragma('vm:prefer-inline')
String canonicalizeMethod(String method) {
  final normalized = method.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(method, 'method', 'Method must not be empty.');
  }
  return normalized.toUpperCase();
}
