// LRU cache for route match results.
// ignore_for_file: public_member_api_docs

/// A fixed-capacity LRU cache backed by an access-ordered [LinkedHashMap].
class RouteCache<K, V> {
  RouteCache(this.capacity) : assert(capacity > 0);

  final int capacity;
  final _map = <K, V>{};

  V? get(K key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value; // re-insert to mark as recently used
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    if (_map.length >= capacity) _map.remove(_map.keys.first);
    _map[key] = value;
  }

  void clear() => _map.clear();
}
