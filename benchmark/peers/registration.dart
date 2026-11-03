// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:roux/roux.dart' as roux;
import 'package:relic_core/relic_core.dart' as relic;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as sr;
import '../registration.dart' as b;

typedef Handler = shelf.Response Function(shelf.Request);
shelf.Response handler(shelf.Request req) => shelf.Response.ok('ok');
typedef Entry = ({String pattern, String method, relic.Method relicMethod});

b.Registration route(String kind, int i) {
  if (kind == 'opaque') {
    final token =
        'service-${(i * 2654435761).toRadixString(36).padLeft(10, 'x')}-region';
    return (
      pattern: '/clients/$token/assets/:id/revisions/:order',
      probe: '/clients/$token/assets/42/revisions/7',
      method: 'GET',
    );
  }
  if (kind == 'heads') {
    return (
      pattern: '/tenant$i/items/:id',
      probe: '/tenant$i/items/42',
      method: 'GET',
    );
  }
  if (kind == 'deep') {
    final p =
        '/v1/orgs/team${i % 17}/projects/$i/releases/current/artifacts/main';
    return (pattern: p, probe: p, method: 'GET');
  }
  if (kind == 'mixed') {
    final id = i ~/ 4;
    return switch (i % 4) {
      0 => (
        pattern: '/api/org/$id/users/:id',
        probe: '/api/org/$id/users/42',
        method: 'GET',
      ),
      1 => (
        pattern: '/api/logs/$id/:order/status',
        probe: '/api/logs/$id/7/status',
        method: 'POST',
      ),
      2 => (
        pattern: '/api/releases/$id/current',
        probe: '/api/releases/$id/current',
        method: 'GET',
      ),
      _ => (
        pattern: '/api/$id/file/:id/rev/:order',
        probe: '/api/$id/file/42/rev/7',
        method: 'PUT',
      ),
    };
  }
  return b.registration(kind, i);
}

Entry entry(String target, String kind, int i) {
  final e = route(kind, i);
  final p = target == 'shelf'
      ? e.pattern.replaceAll(':id', '<id>').replaceAll(':order', '<order>')
      : e.pattern;
  final m = switch (e.method) {
    'GET' => relic.Method.get,
    'PUT' => relic.Method.put,
    'POST' => relic.Method.post,
    _ => relic.Method.delete,
  };
  return (pattern: p, method: e.method, relicMethod: m);
}

void reset(String target) {
  if (target == 'relic') relic.NormalizedPath.interned = relic.LruCache(10000);
  if (target == 'relic-nocache') {
    relic.NormalizedPath.interned = const relic.NoCache();
  }
}

Object build(String target, Iterable<Entry> entries) {
  if (target == 'roux') {
    final r = roux.Router<Handler>();
    for (final e in entries) {
      r.add(e.pattern, handler, method: e.method);
    }
    return r;
  }
  if (target == 'shelf') {
    final r = sr.Router();
    for (final e in entries) {
      r.add(e.method, e.pattern, handler);
    }
    return r;
  }
  final r = relic.Router<Handler>();
  for (final e in entries) {
    r.add(e.relicMethod, e.pattern, handler);
  }
  return r;
}

Future<void> check(Object table, String kind, int n) async {
  for (final i in [0, n ~/ 2, n - 1]) {
    final p = route(kind, i);
    final m = entry('roux', kind, i).relicMethod;
    if (table is roux.Router<Handler>) {
      if (table.find(p.probe, method: p.method)?.data != handler) {
        throw StateError(p.probe);
      }
    } else if (table is relic.Router<Handler>) {
      if (table.lookup(m, p.probe) is! relic.RouterMatch<Handler>) {
        throw StateError(p.probe);
      }
    } else if ((await (table as sr.Router)(
          shelf.Request(p.method, Uri.parse('http://localhost${p.probe}')),
        )).statusCode !=
        200) {
      throw StateError(p.probe);
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 3 ||
      args.length > 4 ||
      !const {'roux', 'relic', 'relic-nocache', 'shelf'}.contains(args.first) ||
      (args.length == 4 && args.last != 'rss')) {
    throw ArgumentError(
      'Expected <roux|relic|relic-nocache|shelf> <workload> <count> [rss]',
    );
  }
  final target = args[0], kind = args[1], n = int.parse(args[2]);
  const shelfWorkloads = {
    'static',
    'params',
    'methods',
    'mixed',
    'heads',
    'deep',
    'opaque',
  };
  if (target == 'shelf' && !shelfWorkloads.contains(kind)) {
    throw ArgumentError.value(
      kind,
      'workload',
      'For shelf, use one of ${shelfWorkloads.join(', ')}',
    );
  }
  if (n < 0 || (n == 0 && args.length != 4)) {
    throw ArgumentError.value(n, 'count');
  }
  final input = Iterable.generate(n, (i) => entry(target, kind, i));
  if (args.length == 4) {
    reset(target);
    final before = ProcessInfo.maxRss;
    final table = build(target, input);
    final peak = ProcessInfo.maxRss;
    if (n > 0) await check(table, kind, n);
    print('$target $kind $n ${peak - before} $peak');
    return;
  }
  final entries = input.toList();
  final times = <double>[];
  for (var k = 0; k < 8; k++) {
    reset(target);
    final t = Stopwatch()..start();
    final table = build(target, entries);
    t.stop();
    await check(table, kind, n);
    if (k > 0) times.add(t.elapsedTicks * 1e9 / t.frequency / n);
  }
  times.sort();
  print('$target $kind $n ${times[3].toStringAsFixed(1)}');
}
