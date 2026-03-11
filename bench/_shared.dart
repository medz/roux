import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;

enum Target { roux, relic }

Target parseTarget(List<String> args) {
  if (args.isEmpty) {
    throw ArgumentError('Expected target: roux or relic');
  }
  return switch (args.first.toLowerCase()) {
    'roux' => Target.roux,
    'relic' => Target.relic,
    _ => throw ArgumentError('Unknown target: ${args.first}'),
  };
}

int parseIntArg(List<String> args, int index, int fallback) {
  if (index >= args.length) return fallback;
  final parsed = int.tryParse(args[index]);
  if (parsed == null) {
    throw ArgumentError('Expected an integer at arg $index: ${args[index]}');
  }
  if (parsed <= 0) {
    throw ArgumentError(
      'Expected a positive integer at arg $index: ${args[index]}',
    );
  }
  return parsed;
}

void printHeader(
  String name,
  Target target, {
  required int routeCount,
  required int queryCount,
  String? note,
}) {
  print('benchmark=$name');
  print('target=${target.name}');
  print('routeCount=$routeCount');
  print('queryCount=$queryCount');
  if (note != null) print('note=$note');
  print('lower is better (us)');
}

void consumeStringParams(Map<String, String>? params, void Function(int) sink) {
  if (params == null) return;
  sink(params.length);
  for (final entry in params.entries) {
    sink(entry.key.length);
    sink(entry.value.length);
  }
}

void consumeSymbolParams(Map<Symbol, String> params, void Function(int) sink) {
  sink(params.length);
  for (final entry in params.entries) {
    sink(entry.key.hashCode);
    sink(entry.value.length);
  }
}

roux.RouteMatch<T> requireRouxMatch<T>(
  roux.RouteMatch<T>? match,
  String path,
  String method,
) {
  if (match != null) return match;
  throw StateError('Expected router match for benchmark $method $path');
}

relic.RouterMatch<T> requireRelicMatch<T>(Object result, String path) {
  if (result is relic.RouterMatch<T>) return result;
  throw StateError('Expected router match for benchmark path: $path');
}

class Request {
  final String path;
  final bool needsParams;

  const Request(this.path, this.needsParams);
}

abstract class SingleScenarioBenchmark extends BenchmarkBase {
  SingleScenarioBenchmark(this.target, String name)
    : super('$name;${target.name}');

  final Target target;
  var _ran = false;

  @override
  void exercise() {
    _ran = true;
    run();
  }

  void verifyRan() {
    if (!_ran) throw StateError('benchmark did not run');
  }
}
