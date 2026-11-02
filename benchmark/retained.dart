import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'registration.dart';

/// Run with `dart run --enable-vm-service=0 benchmark/retained.dart static 8192`.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected a workload and a route count');
  }
  final kind = args.first, n = int.parse(args[1]);
  if (n < 1) throw ArgumentError.value(n, 'route count');
  final uri = (await Service.getInfo()).serverUri;
  if (uri == null) {
    throw StateError('Enable the Dart VM service to measure the heap');
  }
  final isolate = Service.getIsolateId(Isolate.current)!;
  final client = HttpClient();
  Future<Map<String, dynamic>> rpc(
    String name,
    Map<String, String> parameters,
  ) async {
    final url = uri
        .resolve(name)
        .replace(queryParameters: {'isolateId': isolate, ...parameters});
    final response = await (await client.getUrl(url)).close();
    final reply = jsonDecode(await utf8.decoder.bind(response).join());
    if (reply['error'] != null) throw StateError('$name: ${reply['error']}');
    return reply['result'];
  }

  try {
    final router = buildTable(
      Iterable.generate(n, (i) => registration(kind, i)),
    );
    await rpc('getAllocationProfile', {'gc': 'true'});
    // This diagnostic VM RPC reports objects kept alive exclusively by the table.
    final size = await rpc('_getRetainedSize', {
      'targetId': Service.getObjectId(router)!,
    });
    checkTable(router, kind, n);
    final bytes = int.parse(size['valueAsString'] as String);
    print('$kind $n routes: $bytes retained bytes');
  } finally {
    client.close(force: true);
  }
}
