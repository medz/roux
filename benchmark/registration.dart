import 'dart:io';

import 'package:roux/roux.dart';

typedef Registration = ({String pattern, String probe, String method});

const workloads = [
  'static',
  'params',
  'wildcard',
  'nested',
  'indexed',
  'methods',
  'optional',
];

Registration registration(String kind, int i) {
  final path = '/api/$i';
  final method = kind == 'methods'
      ? const ['GET', 'POST', 'PUT', 'DELETE'][i % 4]
      : 'GET';
  final (pattern, probe) = switch (kind) {
    'static' => (path, path),
    'params' => ('$path/users/:id/orders/:order', '$path/users/42/orders/7'),
    'wildcard' => ('$path/**:tail', '$path/images/logo'),
    'nested' => (
      '$path/:id'
          r'(([A-Za-z]+)-(\d+))',
      '$path/Report-42',
    ),
    'indexed' => (
      '/rx/:id(v${i}_'
          r'\d+)',
      '/rx/v${i}_42',
    ),
    'methods' => ('/items/${i ~/ 4}', '/items/${i ~/ 4}'),
    'optional' => ('$path{/:id}?', '$path/42'),
    _ => throw ArgumentError.value(kind, 'workload'),
  };
  return (pattern: pattern, probe: probe, method: method);
}

Router<int> buildTable(Iterable<Registration> entries) {
  final router = Router<int>();
  var i = 0;
  for (final entry in entries) {
    router.add(entry.pattern, i++, method: entry.method);
  }
  return router;
}

void checkTable(Router<int> router, String kind, int n) {
  for (final i in [0, n ~/ 2, n - 1]) {
    final entry = registration(kind, i);
    if (router.find(entry.probe, method: entry.method)?.data != i) {
      throw StateError('Wrong handler for ${entry.method} ${entry.probe}');
    }
  }
}

/// Compile to AOT. Run with a workload, a route count, and optionally "rss".
void main(List<String> args) {
  final n = args.length > 1 ? int.parse(args[1]) : 4096;
  if (n < 1 || args.length > 3 || args.length == 3 && args[2] != 'rss') {
    throw ArgumentError('Expected [workload] [positive route count] [rss]');
  }
  for (final kind in args.isEmpty ? workloads : [args.first]) {
    final input = Iterable.generate(n, (i) => registration(kind, i));
    if (args.length == 3) {
      final before = ProcessInfo.maxRss;
      final router = buildTable(input);
      final peak = ProcessInfo.maxRss;
      checkTable(router, kind, n);
      print(
        '$kind $n routes: peak RSS $peak bytes, growth ${peak - before} bytes',
      );
      continue;
    }
    final entries = input.toList();
    final times = <double>[];
    for (var run = 0; run < 8; run++) {
      final clock = Stopwatch()..start();
      final router = buildTable(entries);
      clock.stop();
      checkTable(router, kind, n);
      if (run > 0) times.add(clock.elapsedTicks * 1e9 / clock.frequency / n);
    }
    times.sort();
    print('$kind $n routes: ${times[3].toStringAsFixed(1)} ns/add');
  }
}
