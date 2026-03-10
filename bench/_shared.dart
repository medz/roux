import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:relic/relic.dart' as relic;
import 'package:roux/roux.dart' as roux;
import 'package:spanner/spanner.dart' as spanner;

enum Target { roux, relic, spanner }

Target parseTarget(List<String> args) {
  if (args.isEmpty) {
    throw ArgumentError('Expected target: roux or relic');
  }
  return switch (args.first.toLowerCase()) {
    'roux' => Target.roux,
    'relic' => Target.relic,
    'spanner' => Target.spanner,
    _ => throw ArgumentError('Unknown target: ${args.first}'),
  };
}

int parseIntArg(List<String> args, int index, int fallback) {
  if (index >= args.length) return fallback;
  return int.tryParse(args[index]) ?? fallback;
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

void consumeDynamicParams(
  Map<String, dynamic> params,
  void Function(int) sink,
) {
  sink(params.length);
  for (final entry in params.entries) {
    sink(entry.key.length);
    sink('${entry.value}'.length);
  }
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

  @override
  void exercise() => run();
}

String? prepareComparablePath(
  String path, {
  required bool decode,
  required bool normalize,
  required bool ignoreCase,
}) {
  if (decode && path.contains('%')) {
    try {
      path = Uri.decodeFull(path);
    } on ArgumentError {
      return null;
    }
  }
  if (!path.startsWith('/')) return null;
  if (normalize) {
    final normalized = normalizeForBench(path);
    if (normalized == null) return null;
    path = normalized;
  } else if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return ignoreCase ? path.toLowerCase() : path;
}

String? normalizeForBench(String path) {
  if (path.isEmpty || !path.startsWith('/')) return null;
  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.isEmpty ? '/' : '/${segments.join('/')}';
}

relic.Method constGetMethod() => relic.Method.get;

spanner.HTTPMethod constGetHttpMethod() => spanner.HTTPMethod.GET;

roux.Router<int> newRouxRouter({
  bool caseSensitive = true,
  bool decodePath = false,
  bool normalizePath = false,
}) => roux.Router<int>(
  caseSensitive: caseSensitive,
  decodePath: decodePath,
  normalizePath: normalizePath,
);
