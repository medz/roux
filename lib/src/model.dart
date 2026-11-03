// ignore_for_file: public_member_api_docs

import 'dart:collection';
import 'segment_program.dart';

class RouteMatch<T> {
  final T data;
  final Map<String, String> params;
  RouteMatch(this.data, this.params);
}

class Captures extends MapBase<String, String> {
  String? _k1, _v1, _k2, _v2, _k3, _v3;
  Map<String, String>? _map;
  @override
  String? operator [](Object? key) {
    if (_map case final m?) return m[key];
    if (_k1 == key) return _v1;
    if (_k2 == key) return _v2;
    return _k3 == key ? _v3 : null;
  }

  @override
  void operator []=(String k, String v) {
    if (_map case final m?) {
      m[k] = v;
    } else if (_k1 == null || _k1 == k) {
      _k1 = k;
      _v1 = v;
    } else if (_k2 == null || _k2 == k) {
      _k2 = k;
      _v2 = v;
    } else if (_k3 == null || _k3 == k) {
      _k3 = k;
      _v3 = v;
    } else {
      _full[k] = v;
    }
  }

  Map<String, String> get _full {
    if (_map case final m?) return m;
    final m = {
      if (_k1 != null) _k1!: _v1!,
      if (_k2 != null) _k2!: _v2!,
      if (_k3 != null) _k3!: _v3!,
    };
    _k1 = _v1 = _k2 = _v2 = _k3 = _v3 = null;
    return _map = m;
  }

  @override
  Iterable<String> get keys => _full.keys;
  @override
  String? remove(Object? k) => _full.remove(k);
  @override
  void clear() => _full.clear();
}

// A lone entry needs no map. Siblings are indexed from the first entry.
class RouteEntry<E extends RouteEntry<E>> {
  RouteEntry(this.key);
  final String? key;
  E? get entry => null;
  Map<String, E>? _siblings;

  @pragma('vm:prefer-inline')
  E? operator [](String name) => name == key ? entry : _siblings?[name];
  E addSibling(E value) => (_siblings ??= {})[value.key!] = value;

  RouteEntry<E>? without(String name) {
    final siblings = _siblings;
    if (name != key) {
      siblings?.remove(name);
      if (siblings?.isEmpty ?? false) _siblings = null;
      if (key != null) return this;
    }
    if (siblings == null || siblings.isEmpty) return null;
    if (siblings.length == 1) return siblings.values.first;
    // Detach the removed entry without scanning a wide table for a new head.
    return key == null ? this : (RouteEntry<E>(null).._siblings = siblings);
  }

  @pragma('vm:prefer-inline')
  E? forMethod(String method) =>
      key == method || (key == '' && _siblings == null)
      ? entry
      : _siblings?[method] ?? this[normalizeMethod(method)] ?? this[''];
}

class RouterNode<T> extends RouteEntry<RouterNode<T>> {
  RouterNode([super.key = '']);
  @override
  RouterNode<T> get entry => this;
  RouteEntry<RouterNode<T>>? statics;
  RouterNode<T>? param, wildcard;
  RouteEntry<RouteData<T>>? methods;

  @pragma('vm:prefer-inline')
  RouterNode<T>? staticChild(String segment, bool sensitive) {
    final children = statics;
    if (children == null) return null;
    final exact = children[segment];
    if (exact != null || sensitive) return exact;
    final folded = segment.toLowerCase();
    return identical(folded, segment) ? null : children[folded];
  }

  bool get isEmpty =>
      statics == null && param == null && wildcard == null && methods == null;
}

class RouteBucket<T> {
  RouteBucket(RouteData<T> first) : routes = [first] {
    final pattern = first.lastConstraint;
    final width = pattern?.prefix.length ?? 0;
    if (width > 0 || pattern?.fixedLength != null) _width = _skip = width;
  }
  final List<RouteData<T>> routes;
  Map<int, RouteData<T>>? _groups;
  Map<int, List<RouteData<T>>>? _ties;
  // Zero groups by exact segment length. A positive width groups by literal prefix.
  int? _width;
  // Every candidate verifies its whole regex, so index only the differing prefix units.
  int _skip = 0;

  void add(RouteData<T> route) {
    routes.add(route);
    final pattern = route.lastConstraint;
    final prefix = pattern?.prefix ?? '';
    final prefixWidth = prefix.length;
    final width = _width;
    if (width == null) return;
    // shortcut: scan mixed constraints in registration order, index them if profiles warrant it.
    if (route.constraintDepth != routes.first.constraintDepth ||
        (width == 0 ? pattern?.fixedLength == null : prefixWidth == 0)) {
      _width = null;
      _groups = null;
      _ties = null;
    } else {
      final end = prefixWidth < width ? prefixWidth : width,
          first = routes.first.lastConstraint!.prefix;
      var skip = 0;
      while (skip < end &&
          skip < _skip &&
          prefix.codeUnitAt(skip) == first.codeUnitAt(skip)) {
        skip++;
      }
      if (_groups != null && end == width && skip == _skip) {
        _index(route);
        return;
      }
      _skip = skip;
      _width = end;
      _groups = {};
      _ties = null;
      for (final entry in routes) {
        _index(entry);
      }
    }
  }

  void _index(RouteData<T> route) {
    final pattern = route.lastConstraint!;
    final key = _groupKey(pattern.prefix, pattern.fixedLength);
    final group = _groups!, first = group[key];
    if (first == null) {
      group[key] = route;
    } else {
      ((_ties ??= {})[key] ??= [first]).add(route);
    }
  }

  RouteMatch<T>? match(List<String> segments, bool optionalTail) {
    List<RouteData<T>>? ties;
    final groups = _groups;
    if (groups != null) {
      final i = routes.first.constraintDepth - 1, width = _width!;
      if (i >= segments.length) return null;
      final text = segments[i];
      if (text.length < width) return null;
      final key = _groupKey(text, text.length);
      if (key != -1) {
        final first = groups[key];
        if (first == null) return null;
        ties = _ties?[key];
        if (ties == null) {
          return first.match(segments, optionalTail: optionalTail);
        }
      }
    }
    RouteMatch<T>? best;
    var bestDepth = -1;
    for (final route in ties ?? routes) {
      final depth = route.constraintDepth;
      if (depth <= bestDepth) continue;
      final found = route.match(segments, optionalTail: optionalTail);
      if (found == null) continue;
      if (ties != null || route.plan == null || depth == segments.length) {
        return found;
      }
      best = found;
      bestDepth = depth;
    }
    return best;
  }

  @pragma('vm:prefer-inline')
  int _groupKey(String text, int? length) {
    final width = _width!;
    if (width == 0) return length!;
    var hash = 0;
    for (var i = _skip; i < width; i++) {
      final c = text.codeUnitAt(i);
      if (c >= 128) return -1;
      hash = (hash * 31 + (c | 32)) & 0x3fffffff;
    }
    return hash;
  }
}

class Wildcard {
  Wildcard(this.key, this.optional, this.rest);
  final String key;
  final bool optional, rest;
}

class RouteData<T> extends RouteEntry<RouteData<T>> {
  @override
  RouteData<T> get entry => this;
  RouteData(super.key, this.data);
  final T data;
  // A single capture uses its key directly. Longer plans store the gaps between keys.
  Object? plan;
  int captureStart = 0;
  RouteBucket<T>? alternatives;
  int constraintDepth = 0;
  SegmentPattern? lastConstraint;
}

extension RouteMatching<T> on RouteData<T> {
  @pragma('vm:prefer-inline')
  RouteMatch<T>? match(
    List<String> segments, {
    bool allowPartial = false,
    bool optionalTail = false,
  }) {
    final item = plan, items = item is List<Object> ? item : null;
    if (optionalTail) {
      final tail = items?.last ?? item;
      if (tail is! Wildcard || !tail.optional) return null;
    }
    final captures = Captures();
    var index = captureStart;
    final count = items?.length ?? (item == null ? 0 : 1);
    for (var n = 0; n < count; n++) {
      final key = items == null ? item : items[n];
      if (key is int) {
        index += key;
        continue;
      }
      final wildcard = key is Wildcard ? key : null;
      final value = index < segments.length ? segments[index] : '';
      if (key is SegmentPattern) {
        if (!key.capture(value, captures) && !allowPartial) return null;
      } else if (wildcard == null || wildcard.rest || value.isNotEmpty) {
        final name = wildcard?.key ?? key as String;
        captures[name] = wildcard?.rest == true && index + 1 < segments.length
            ? segments.sublist(index).join('/')
            : value;
      }
      index++;
    }
    return RouteMatch(data, captures);
  }
}

String normalizeMethod(String? method) {
  if (method == null) return '';
  for (var i = 0; i < method.length; i++) {
    final c = method.codeUnitAt(i);
    if (c < 65 || c > 90) return method.trim().toUpperCase();
  }
  return method;
}
