import 'node.dart';

List<String> splitPath(String path) {
  final parts = path.split('/');
  if (parts.isEmpty) {
    return const [];
  }
  final segments = parts.sublist(1);
  if (segments.isNotEmpty && segments.last.isEmpty) {
    segments.removeLast();
  }
  return segments;
}

String normalizePatternPath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != 47) {
    path = '/$path';
  }
  return path.replaceAll(r'\:', '%3A');
}

void setParamRegexp(List<RegExp?> paramsRegexp, int index, RegExp regexp) {
  if (paramsRegexp.length <= index) {
    paramsRegexp.length = index + 1;
  }
  paramsRegexp[index] = regexp;
}

T requireData<T>(T? data) {
  if (data != null || null is T) {
    return data as T;
  }
  throw ArgumentError(
    'Route data is required when using a non-nullable router type.',
  );
}

MatchedRoute<T> toMatched<T>(MethodData<T> match, List<String> segments) {
  if (match.paramsMap == null) {
    return MatchedRoute<T>(match.data);
  }
  return MatchedRoute<T>(
    match.data,
    getMatchParams(segments, match.paramsMap!),
  );
}

Map<String, String> getMatchParams(
  List<String> segments,
  ParamsIndexMap paramsMap,
) {
  final params = <String, String>{};
  for (final item in paramsMap) {
    final index = item.index;
    final name = item.name;
    String segment;
    if (index < 0) {
      final start = -(index + 1);
      segment = start < segments.length
          ? segments.sublist(start).join('/')
          : '';
    } else {
      segment = index < segments.length ? segments[index] : '';
    }

    if (name is String) {
      params[name] = segment;
      continue;
    }

    if (name is RegExp) {
      final match = name.firstMatch(segment);
      if (match == null) {
        continue;
      }

      for (final key in match.groupNames) {
        final value = match.namedGroup(key);
        if (value != null) {
          params[key] = value;
        }
      }
    }
  }
  return params;
}
