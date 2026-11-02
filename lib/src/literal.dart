// ignore_for_file: public_member_api_docs

import 'model.dart';
import 'path.dart';

final _nil = Object();

class _Variants<T> {
  _Variants(this.values);
  final List<T> values;
}

class _Methods {
  _Methods(this.a);
  Object? a, b, c, d;
  Map<String, Object>? more;
  Object? get(int slot, String method) => switch (slot) {
    0 => a,
    1 => b,
    2 => c,
    3 => d,
    _ => more?[method],
  };
  void put(int slot, String method, Object? value) => switch (slot) {
    0 => a = value,
    1 => b = value,
    2 => c = value,
    3 => d = value,
    _ when value == null => more?.remove(method),
    _ => (more ??= {})[method] = value,
  };
}

class Bindings<T> {
  var _rows = <String, Object>{};
  final _names = <String>[];
  int _deletions = 0;
  bool get isEmpty => _rows.isEmpty;
  bool contains(String key) => _rows.containsKey(key);
  T _value(Object item) => (identical(item, _nil) ? null : item) as T;
  Object _append(Object? old, T data) {
    if (old == null) return data ?? _nil;
    if (old is _Variants<T>) {
      old.values.add(data);
      return old;
    }
    return _Variants<T>([_value(old), data]);
  }

  void add(String key, String method, T data) {
    final old = _rows[key];
    if (_names.isEmpty) _names.add(method);
    if (method == _names.first && old is! _Methods) {
      _rows[key] = _append(old, data);
      return;
    }
    final row = old is _Methods ? old : (_rows[key] = _Methods(old));
    var slot = _names.indexOf(method);
    if (slot < 0 && _names.length < 4) {
      slot = _names.length;
      _names.add(method);
    }
    row.put(slot, method, _append(row.get(slot, method), data));
  }

  bool remove(String key, String method) {
    final row = _rows[key];
    if (row == null) return false;
    if (row is _Methods) {
      final slot = _names.indexOf(method);
      if (row.get(slot, method) == null) return false;
      row.put(slot, method, null);
      if (row.b != null ||
          row.c != null ||
          row.d != null ||
          row.more?.isNotEmpty == true) {
        return true;
      }
      if (row.a case final a?) {
        _rows[key] = a;
        return true;
      }
    } else if (method != _names.first) {
      return false;
    }
    _drop(key);
    if (_rows.isEmpty) _names.clear();
    return true;
  }

  Object? _drop(String key) {
    final row = _rows.remove(key);
    if (++_deletions > _rows.length) {
      _rows = Map.of(_rows);
      _deletions = 0;
    }
    return row;
  }

  Object? _cell(Object row, String key) => row is _Methods
      ? row.get(_names.indexOf(key), key)
      : (key == _names.first ? row : null);
  Object? findCell(String key, String method) {
    final row = _rows[key];
    if (row == null) return null;
    if (row is! _Methods) {
      final name = _names.first;
      return name.isEmpty || name == method || name == normalizeMethod(method)
          ? row
          : null;
    }
    final exact = _cell(row, method);
    if (exact != null) return exact;
    final norm = normalizeMethod(method);
    return (norm != method ? _cell(row, norm) : null) ?? _cell(row, '');
  }

  T value(Object cell) =>
      cell is _Variants<T> ? cell.values.first : _value(cell);
  RouteMatch<T>? literal(String key, String method) {
    final cell = findCell(key, method);
    return cell == null ? null : RouteMatch(value(cell), Captures());
  }

  void _forValues(Object? cell, void Function(T) visit) {
    if (cell is _Variants<T>) {
      cell.values.forEach(visit);
    } else if (cell != null) {
      visit(_value(cell));
    }
  }

  void allValues(
    String key,
    String method,
    bool includeAny,
    void Function(T) visit,
  ) {
    final row = _rows[key];
    if (row == null) return;
    final exact = _cell(row, method);
    if (method.isNotEmpty && (includeAny || exact == null)) {
      _forValues(_cell(row, ''), visit);
    }
    _forValues(exact, visit);
  }

  void rekey(String from, String to) {
    _rows[to] = _rows.remove(from)!;
  }

  void take(String key, void Function(String, T) insert) {
    final row = _drop(key);
    if (row is _Methods) {
      for (var i = 0; i < _names.length; i++) {
        _forValues(row.get(i, _names[i]), (v) => insert(_names[i], v));
      }
      row.more?.forEach((m, c) => _forValues(c, (v) => insert(m, v)));
    } else {
      _forValues(row, (v) => insert(_names.first, v));
    }
  }
}

class LiteralRoutes<T> extends Bindings<T> {
  int _heads = 0, _depths = 0;
  bool hasHead(int c) => c >= 128 || _heads & (1 << (c & 31)) != 0;
  @pragma('vm:prefer-inline')
  bool possible(String path) => path.length > 1 && hasHead(path.codeUnitAt(1));
  void addLiteral(String key, String method, T data, int depth) {
    final h = key.codeUnitAt(1) & 31;
    _heads |= 1 << h;
    _depths |= 1 << (depth & 31);
    add(key, method, data);
  }

  @pragma('vm:prefer-inline')
  String? normalizedKey(String raw, List<String> parts, bool sensitive) {
    if (parts.isEmpty ||
        !hasHead(parts.first.codeUnitAt(0)) ||
        _depths & (1 << (parts.length & 31)) == 0) {
      return null;
    }
    var len = 0;
    for (final s in parts) {
      len += s.length + 1;
    }
    final key = raw.length == len && raw.startsWith('/')
        ? raw
        : '/${parts.join('/')}';
    final normalized = literalCase(key, sensitive);
    return normalized == raw ? null : normalized;
  }

  void collectLiterals(
    String raw,
    List<String> parts,
    bool sensitive,
    String method,
    bool includeAny,
    List<RouteMatch<T>> matches,
  ) {
    var key = raw;
    if (!possible(raw) || !contains(raw)) {
      final normalized = normalizedKey(raw, parts, sensitive);
      if (normalized == null) return;
      key = normalized;
    }
    allValues(
      key,
      method,
      includeAny,
      (value) => matches.add(RouteMatch(value, Captures())),
    );
  }
}
