import 'package:roux/roux.dart';

void main() => runLookups(Router<int>());

/// Runs the same workload against a caller-supplied router, including older versions.
void runLookups(Router<int> router) {
  for (var i = 0; i < 512; i++) {
    router.add('/api/items/$i', i, method: 'GET');
  }
  router.add('/users/:id/orders/:order', 1, method: 'GET');
  router.add(r'/numbers/:id(\d+)', 2, method: 'GET');
  for (var i = 0; i < 32; i++) {
    router.add(
      '/rx/:id(v${i}_'
      r'\d+)',
      i,
      method: 'GET',
    );
  }
  router.add('/files/**', 1);
  router.add('/files/:id', 2);
  router.add('/files/static', 3);
  router.add(r'/nested/:id(([A-Za-z]+)-(\d+))', 4);

  int find(String path) {
    final m = router.find(path, method: 'GET');
    return m == null ? -1 : m.data + (m.params['id']?.length ?? 0);
  }

  int findAll(String path) => router
      .findAll(path, method: 'GET')
      .fold(0, (sum, m) => sum + m.data + (m.params['id']?.length ?? 0));

  final workloads = <(String, List<String>, int Function(String))>[
    ('static', List.generate(512, (i) => '/api/items/$i'), find),
    ('params', List.generate(4096, (i) => '/users/$i/orders/${i + 7}'), find),
    (
      'normalized',
      List.generate(4096, (i) => 'users//tmp/../$i/./orders/${i + 7}/'),
      find,
    ),
    ('miss', List.generate(4096, (i) => '/missing/$i'), find),
    ('regex', List.generate(4096, (i) => '/numbers/$i'), find),
    ('regex32', List.generate(4096, (i) => '/rx/v${i % 32}_$i'), find),
    (
      'findAll',
      List.generate(512, (i) => i.isEven ? '/files/static' : '/files/$i'),
      findAll,
    ),
  ];
  const count = 131072;
  for (final (name, paths, lookup) in workloads) {
    _measure(name, count, (i) => lookup(paths[i % paths.length]));
  }
  for (final stride in [1, 2, 20]) {
    _measure('mixed ${100 - 100 ~/ stride}% fixed', workloads.length * count, (
      i,
    ) {
      final (_, paths, lookup) = workloads[i % workloads.length];
      final request = i ~/ workloads.length;
      final path = request % stride == 0
          ? paths[(request ~/ stride) % paths.length]
          : paths.first;
      return lookup(path);
    });
  }
  for (final path in ['/numbers/42', '/rx/v31_42', '/nested/Report-42']) {
    _measure('hot $path', count, (_) => find(path));
  }
}

void _measure(String name, int count, int Function(int) lookup) {
  final samples = <double>[];
  var checksum = 0;
  for (var round = 0; round < 8; round++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      checksum += lookup(i);
    }
    watch.stop();
    if (round > 0) {
      samples.add(watch.elapsedTicks * 1e9 / watch.frequency / count);
    }
  }
  samples.sort();
  print('$name  ${samples[3].toStringAsFixed(1)} ns/op  checksum=$checksum');
}
