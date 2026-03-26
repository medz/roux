import 'model.dart';

abstract interface class Cache<T> {
  RouteMatch<T>? get(String key);
  void put(String key, RouteMatch<T> value);
  void clear();
}

class LRUCache<T> implements Cache<T> {
  LRUCache([this.capacity = 256]) : assert(capacity > 0);

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
