import 'model.dart';

/// Cache interface for memoizing route lookup results.
abstract interface class Cache<T> {
  /// Returns a cached match for [key], if present.
  RouteMatch<T>? get(String key);

  /// Stores [value] under [key].
  void put(String key, RouteMatch<T> value);

  /// Clears all cached entries.
  void clear();
}

/// A fixed-capacity cache that evicts the oldest stored entry.
class LRUCache<T> implements Cache<T> {
  /// Creates a cache with the given maximum number of entries.
  LRUCache([this.capacity = 256]) : assert(capacity > 0);

  /// Maximum number of entries retained by the cache.
  final int capacity;
  late final _cache = <String, RouteMatch<T>>{};

  @override
  RouteMatch<T>? get(String key) => _cache[key];

  @override
  void put(String key, RouteMatch<T> value) {
    if (!_cache.containsKey(key) && _cache.length >= capacity) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = value;
  }

  @override
  void clear() => _cache.clear();
}
