// Adds one new route to each prebuilt table. Setup and lookup checks stay outside the timer.
import 'package:relic_core/relic_core.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as sr;

import 'registration.dart' as b;

void main(List<String> args) async {
  final target = args.single;
  if (!const {'roux', 'relic', 'relic-nocache', 'shelf'}.contains(target)) {
    throw ArgumentError.value(target, 'target');
  }
  for (final size in [128, 8192]) {
    final entries = List.generate(size, (i) => b.entry(target, 'params', i));
    final middle = size ~/ 2;
    final extra = target == 'shelf'
        ? '/api/$middle/handoff/<id>'
        : '/api/$middle/handoff/:id';
    final probe = '/api/$middle/handoff/42';
    final samples = <double>[];
    for (var run = 0; run < 39; run++) {
      b.reset(target);
      final table = b.build(target, entries);
      final t = Stopwatch();
      if (table is roux.Router<b.Handler>) {
        t.start();
        table.add(extra, b.handler, method: 'POST');
        t.stop();
        if (table.find(probe, method: 'POST')?.data != b.handler) {
          throw StateError(probe);
        }
      } else if (table is relic.Router<b.Handler>) {
        t.start();
        table.add(relic.Method.post, extra, b.handler);
        t.stop();
        if (table.lookup(relic.Method.post, probe)
            is! relic.RouterMatch<b.Handler>) {
          throw StateError(probe);
        }
      } else {
        final router = table as sr.Router;
        t.start();
        router.add('POST', extra, b.handler);
        t.stop();
        if ((await router(
              shelf.Request('POST', Uri.parse('http://localhost$probe')),
            )).statusCode !=
            200) {
          throw StateError(probe);
        }
      }
      if (run % 7 == 0) await b.check(table, 'params', size);
      if (run >= 4) samples.add(t.elapsedTicks * 1e9 / t.frequency);
    }
    samples.sort();
    print('outlier-$size ${samples[samples.length ~/ 2].toStringAsFixed(1)} 1');
  }
}
