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
    if (width > 0 || pattern?.fixedLength != null) _width = width;
  }
  final List<RouteData<T>> routes;
  Map<Object, List<RouteData<T>>>? _groups;
  // Zero groups by exact segment length. A positive width groups by literal prefix.
  int? _width;
  // Every candidate verifies its whole regex, so index only the differing prefix units.
  String _common = '';

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
    } else if (_groups == null ||
        prefixWidth < width ||
        (_common.isNotEmpty && !prefix.startsWith(_common))) {
      final nextWidth = prefixWidth < width ? prefixWidth : width;
      if (_groups == null && nextWidth > 0) {
        final first = routes.first.lastConstraint!.prefix, next = prefix;
        var shared = 0;
        while (shared < nextWidth &&
            first.codeUnitAt(shared) == next.codeUnitAt(shared)) {
          shared++;
        }
        _common = first.substring(0, shared);
      } else if (_common.length > nextWidth || !prefix.startsWith(_common)) {
        _common = '';
      }
      _width = nextWidth;
      _groups = {};
      for (final entry in routes) {
        _index(entry);
      }
    } else {
      _index(route);
    }
  }

  void _index(RouteData<T> route) {
    final pattern = route.lastConstraint!;
    final key = _groupKey(pattern.prefix.toLowerCase(), pattern.fixedLength);
    (_groups![key] ??= []).add(route);
  }

  @pragma('vm:prefer-inline')
  List<RouteData<T>> candidates(List<String> segments) {
    final groups = _groups;
    if (groups == null) return routes;
    final index = routes.first.constraintDepth - 1, width = _width!;
    final value = index < segments.length ? segments[index] : null;
    if (value == null || value.length < width) return const [];
    final key = _groupKey(value, value.length);
    return groups[key] ??
        (key is String ? groups[key.toLowerCase()] : null) ??
        const [];
  }

  @pragma('vm:prefer-inline')
  Object _groupKey(String text, int? length) {
    final width = _width!;
    if (width == 0) return length!;
    final start = _common.length;
    if (width - start > 4) return text.substring(start, width);
    // Four ASCII literal units fit in a 28-bit key on both runtimes.
    var key = 0;
    for (var i = start; i < width; i++) {
      var c = text.codeUnitAt(i);
      if (c >= 128) {
        text = text.substring(0, width).toLowerCase();
        if (text.length != width || (c = text.codeUnitAt(i)) >= 128) return -1;
      }
      key = (key << 7) | (c | 32);
    }
    return key;
  }
}

class Wildcard {
  Wildcard(this.index, this.key, this.optional, this.rest);
  final int index;
  final String key;
  final bool optional, rest;
}

class RouteData<T> extends RouteEntry<RouteData<T>> {
  @override
  RouteData<T> get entry => this;
  RouteData(super.key, this.data);
  final T data;
  // Integers skip literal segments between capture keys.
  List<Object> params = const [];
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
    if (optionalTail) {
      final tail = params.last;
      if (tail is! Wildcard || !tail.optional) return null;
    }
    final captures = Captures();
    var index = 0;
    for (final key in params) {
      if (key is int) {
        index += key;
        continue;
      }
      final wildcard = key is Wildcard ? key : null;
      if (wildcard != null) index = wildcard.index;
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
