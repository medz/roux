import 'node.dart';

List<String> splitPath(String path) {
  final segments = <String>[];
  final length = path.length;
  var start = 0;
  var first = true;

  for (var i = 0; i <= length; i++) {
    if (i != length && path.codeUnitAt(i) != 47) {
      continue;
    }

    if (first) {
      first = false;
    } else {
      segments.add(path.substring(start, i));
    }
    start = i + 1;
  }

  if (segments.isNotEmpty && segments.last.isEmpty) {
    segments.removeLast();
  }
  return segments;
}

String normalizePatternPath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != 47) {
    path = '/$path';
  }
  if (!path.contains(r'\:')) {
    return path;
  }
  return path.replaceAll(r'\:', '%3A');
}

void setParamRegexp(List<RegExp?> paramsRegexp, int index, RegExp regexp) {
  if (paramsRegexp.length <= index) {
    // Grow the list and rely on null fill for gaps between entries.
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
          ? _joinSegmentsFrom(segments, start)
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

String _joinSegmentsFrom(List<String> segments, int start) {
  if (start >= segments.length) {
    return '';
  }

  final sb = StringBuffer(segments[start]);
  for (var i = start + 1; i < segments.length; i++) {
    sb.write('/');
    sb.write(segments[i]);
  }
  return sb.toString();
}
