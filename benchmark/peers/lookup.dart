// ignore_for_file: public_member_api_docs

import 'dart:math';
import 'package:relic_core/relic_core.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as sr;

const count = 256;
typedef Hit = (int, String?, String?);
const miss = (-1, null, null);

void register(void Function(String, int) add, {bool shelfSyntax = false}) {
  for (var i = 0; i < count; i++) {
    add('/api/items/$i', i);
    add(
      shelfSyntax
          ? '/shop/$i/users/<id>/orders/<order>'
          : '/shop/$i/users/:id/orders/:order',
      count + i,
    );
  }
}

List<(String, Hit)> queries(String name) {
  final n = name == 'static'
      ? count
      : name.endsWith('32k')
      ? 32768
      : 4096;
  final qs = List.generate(n, (i) {
    final slot = i % count;
    final id = 'u$i', order = 'o${i + 7}';
    if (name == 'static') return ('/api/items/$slot', (slot, null, null));
    if (name.startsWith('miss')) {
      return ('/shop/$slot/users/$id/missing/$order', miss);
    }
    return ('/shop/$slot/users/$id/orders/$order', (count + slot, id, order));
  });
  qs.shuffle(Random(7001));
  return qs;
}

int score(Hit hit) =>
    hit.$1 + (hit.$2?.length ?? 0) * 31 + (hit.$3?.length ?? 0);
double ns(Stopwatch watch, int n) =>
    watch.elapsedTicks * 1e9 / watch.frequency / n;
void report(String name, List<double> times, int checksum) {
  times.sort();
  print('$name ${times[times.length ~/ 2].toStringAsFixed(1)} $checksum');
}

void pure(String target) {
  late final Hit Function(String) lookup;
  if (target == 'roux') {
    final r = roux.Router<int>();
    register((p, v) => r.add(p, v, method: 'GET'));
    lookup = (p) {
      final m = r.find(p, method: 'GET');
      return m == null ? miss : (m.data, m.params['id'], m.params['order']);
    };
  } else {
    if (target == 'relic-nocache') {
      relic.NormalizedPath.interned = const relic.NoCache();
    }
    final r = relic.Router<int>();
    register(r.get);
    lookup = (p) {
      final m = r.lookup(relic.Method.get, p);
      return m is relic.RouterMatch<int>
          ? (m.value, m.parameters[#id], m.parameters[#order])
          : miss;
    };
  }
  for (final name in [
    'static',
    'params-4k',
    'params-32k',
    'miss-4k',
    'miss-32k',
  ]) {
    final qs = queries(name);
    for (final (path, expected) in qs) {
      if (lookup(path) != expected) throw StateError('$target $name $path');
    }
    final times = <double>[];
    var sum = 0;
    const n = 131072;
    for (var round = 0; round < 8; round++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        sum += score(lookup(qs[i % qs.length].$1));
      }
      sw.stop();
      if (round != 0) times.add(ns(sw, n));
    }
    report(name, times, sum);
  }
}

Future<void> dispatch(String target) async {
  shelf.Response respond(Hit hit) =>
      shelf.Response(hit == miss ? 404 : 200, context: {'hit': hit});
  shelf.Response notFound(shelf.Request req) => respond(miss);
  late final Future<shelf.Response> Function(shelf.Request) handle;
  if (target == 'shelf') {
    final r = sr.Router(notFoundHandler: notFound);
    register(
      (p, v) => r.get(p, (shelf.Request req) {
        final params = sr.RouterParams(req).params;
        return respond((v, params['id'], params['order']));
      }),
      shelfSyntax: true,
    );
    handle = r.call;
  } else {
    final r = roux.Router<int>();
    register((p, v) => r.add(p, v, method: 'GET'));
    handle = (req) async {
      final m = r.find('/${req.url.path}', method: req.method);
      return m == null
          ? notFound(req)
          : respond((m.data, m.params['id'], m.params['order']));
    };
  }
  for (final name in ['static', 'params-4k', 'miss-4k']) {
    final qs = queries(name);
    final reqs = [
      for (final (p, _) in qs)
        shelf.Request('GET', Uri.parse('http://localhost$p')),
    ];
    for (var i = 0; i < reqs.length; i++) {
      if ((await handle(reqs[i])).context['hit'] != qs[i].$2) {
        throw StateError('$target $name ${qs[i]}');
      }
    }
    final times = <double>[];
    var sum = 0;
    const n = 8192;
    for (var round = 0; round < 8; round++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        final res = await handle(reqs[i % reqs.length]);
        sum += score(res.context['hit'] as Hit);
      }
      sw.stop();
      if (round != 0) times.add(ns(sw, n));
    }
    report(name, times, sum);
  }
}

Future<void> main(List<String> args) async {
  final target = args.single;
  if (target == 'shelf' || target == 'roux-shelf') {
    await dispatch(target);
  } else if (const {'roux', 'relic', 'relic-nocache'}.contains(target)) {
    pure(target);
  } else {
    throw ArgumentError.value(target, 'target');
  }
}
