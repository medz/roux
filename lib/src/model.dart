// ignore_for_file: public_member_api_docs

import 'segment_program.dart';

const String unnamedGroupPrefix = '__roux_unnamed_';

class RouteMatch<T> {
  final T data;
  final Map<String, String> params;
  RouteMatch(this.data, this.params);
}

// Most trie nodes have one literal child or one registered HTTP method.
class RouteIndex<V extends Object> {
  RouteIndex(this._key);
  final String _key;
  V? _value;
  Map<String, V>? _others;

  V? operator [](String key) => key == _key ? _value : _others?[key];

  V putIfAbsent(String key, V Function() create) => key == _key
      ? _value ??= create()
      : (_others ??= {}).putIfAbsent(key, create);

  V? remove(String key) {
    if (key != _key) return _others?.remove(key);
    final value = _value;
    _value = null;
    return value;
  }

  bool get isEmpty => _value == null && (_others?.isEmpty ?? true);
}

class RouterNode<T> {
  RouteIndex<RouterNode<T>>? statics;
  RouterNode<T>? param;
  RouterNode<T>? wildcard;
  RouteIndex<RouteBucket<T>>? methods;

  RouterNode<T>? staticChild(String segment, bool caseSensitive) {
    final children = statics;
    if (children == null) return null;
    return children[segment] ??
        (caseSensitive ? null : children[segment.toLowerCase()]);
  }

  bool get isEmpty =>
      statics == null && param == null && wildcard == null && methods == null;
}

class SegmentPattern {
  const SegmentPattern(
    this.regex,
    this.groups, {
    required this.prefix,
    this.separator,
    this.program,
  });

  final RegExp regex;
  final List<CaptureGroup> groups;
  final String prefix;
  int? get fixedLength => program?.fixedLength;
  final String? separator;
  final SegmentProgram? program;

  bool capture(String value, Map<String, String> captures) =>
      program?.capture(value, captures) ?? _captureFallback(value, captures);

  bool _captureFallback(String value, Map<String, String> captures) {
    if (groups.length == 1 && groups.first.index == 0) {
      if (!regex.hasMatch(value)) return false;
      captures[groups.first.key] = value;
      return true;
    }
    if (separator case final sep?) {
      final end = value.length - sep.length - 1;
      if (end < 1) return false;
      // The first capture is greedy and the second must be nonempty.
      final cut = value.lastIndexOf(sep, end);
      if (cut < 1) return false;
      captures[groups.first.key] = value.substring(0, cut);
      captures[groups.last.key] = value.substring(cut + sep.length);
      return true;
    }
    final match = regex.firstMatch(value);
    if (match == null) return false;
    for (final group in groups) {
      final part = group.index == 0
          ? value
          : group.index == null
          ? match.namedGroup(group.name)
          : match[group.index!];
      if (part != null) captures[group.key] = part;
    }
    return true;
  }
}

class RouteBucket<T> {
  final routes = <RouteData<T>>[];
  Map<Object, List<RouteData<T>>>? _groups;
  // Zero groups by exact segment length. A positive width groups by literal prefix.
  int? _width;

  void add(RouteData<T> route) {
    routes.add(route);
    final pattern = route.lastConstraint;
    final prefixWidth = pattern?.prefix.length ?? 0;
    if (routes.length == 1) {
      if (prefixWidth > 0 || pattern?.fixedLength != null) _width = prefixWidth;
      return;
    }
    final width = _width;
    if (width == null) return;
    // shortcut: scan mixed constraints in registration order, index them if profiles warrant it.
    if (route.constraintDepth != routes.first.constraintDepth ||
        (width == 0 ? pattern?.fixedLength == null : prefixWidth == 0)) {
      _width = null;
      _groups = null;
    } else if (_groups == null || prefixWidth < width) {
      if (prefixWidth < width) _width = prefixWidth;
      _groups = {};
      for (final entry in routes) {
        _index(entry);
      }
    } else {
      _index(route);
    }
  }

  void _index(RouteData<T> route) {
    final width = _width!;
    final pattern = route.lastConstraint!;
    final key = width == 0
        ? pattern.fixedLength!
        : pattern.prefix.substring(0, width).toLowerCase();
    (_groups![key] ??= []).add(route);
  }

  List<RouteData<T>> candidates(List<String> segments) {
    final groups = _groups;
    if (groups == null) return routes;
    final index = routes.first.constraintDepth - 1;
    final width = _width!;
    if (index >= segments.length || segments[index].length < width) {
      return const [];
    }
    final value = segments[index];
    if (width == 0) return groups[value.length] ?? const [];
    final key = value.substring(0, width);
    return groups[key] ?? groups[key.toLowerCase()] ?? const [];
  }
}

class ParamSpec {
  ParamSpec(this.index, Object key, this.optional, {this.rest = false})
    : key = key is String ? normalizeUnnamedGroupKey(key) : key;

  final int index;
  final Object key; // String name or SegmentPattern
  final bool optional;
  final bool rest;
}

class RouteData<T> {
  RouteData(this.data, this.params, this.constraintDepth, this.lastConstraint);

  final T data;
  final List<ParamSpec> params;
  final int constraintDepth;
  final SegmentPattern? lastConstraint;

  RouteMatch<T>? match(
    List<String> segments, {
    bool allowPartial = false,
    bool optionalTail = false,
  }) {
    if (optionalTail && !params.last.optional) return null;
    final captures = <String, String>{};
    for (final spec in params) {
      final index = spec.index;
      final segment = index >= segments.length
          ? ''
          : spec.rest && index + 1 < segments.length
          ? segments.getRange(index, segments.length).join('/')
          : segments[index];
      final key = spec.key;
      if (key is String) {
        if (spec.optional && !spec.rest && segment.isEmpty) continue;
        captures[key] = segment;
      } else if (!(key as SegmentPattern).capture(segment, captures) &&
          !allowPartial) {
        return null;
      }
    }
    return RouteMatch(data, captures);
  }
}

String normalizeUnnamedGroupKey(String key) =>
    key.startsWith(unnamedGroupPrefix)
    ? key.substring(unnamedGroupPrefix.length)
    : key;
