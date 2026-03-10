import 'route_model.dart';

String? sanitizeRoutePath(String path) {
  if (!path.startsWith('/')) return null;
  return trimTrailingSlash(path);
}

String? normalizeRoutePath(String path) {
  if (!path.startsWith('/')) return null;
  if (path.length == 1) return path;
  var segmentStart = 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) continue;
    final segmentLength = i - segmentStart;
    if (segmentLength == 0 ||
        (segmentLength == 1 && path.codeUnitAt(segmentStart) == 46) ||
        (segmentLength == 2 &&
            path.codeUnitAt(segmentStart) == 46 &&
            path.codeUnitAt(segmentStart + 1) == 46)) {
      return _normalizeRoutePathSlow(path);
    }
    segmentStart = i + 1;
  }
  final trailingLength = path.length - segmentStart;
  if (trailingLength == 0) return path.substring(0, path.length - 1);
  if ((trailingLength == 1 && path.codeUnitAt(segmentStart) == 46) ||
      (trailingLength == 2 &&
          path.codeUnitAt(segmentStart) == 46 &&
          path.codeUnitAt(segmentStart + 1) == 46)) {
    return _normalizeRoutePathSlow(path);
  }
  return path;
}

String? _normalizeRoutePathSlow(String path) {
  final segments = <String>[];
  var cursor = 1;
  while (cursor < path.length) {
    while (cursor < path.length && path.codeUnitAt(cursor) == slashCode) {
      cursor += 1;
    }
    if (cursor >= path.length) break;
    final segmentEnd = findSegmentEnd(path, cursor);
    final segment = path.substring(cursor, segmentEnd);
    if (segment == '.') {
      cursor = segmentEnd + 1;
      continue;
    }
    if (segment == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
      cursor = segmentEnd + 1;
      continue;
    }
    segments.add(segment);
    cursor = segmentEnd + 1;
  }
  if (segments.isEmpty) return '/';
  return '/${segments.join('/')}';
}

String trimTrailingSlash(String path) {
  return path.length > 1 && path.endsWith('/') && !path.endsWith('//')
      ? path.substring(0, path.length - 1)
      : path;
}

String canonicalizeRoutePath(String path, bool caseSensitive) =>
    caseSensitive ? path : path.toLowerCase();

int findSegmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != slashCode) {
    i += 1;
  }
  return i;
}

bool containsEmptySegments(String path) {
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i - 1) == slashCode &&
        path.codeUnitAt(i) == slashCode) {
      return true;
    }
  }
  return false;
}

int segmentCount(String path) {
  var count = path.length == 1 ? 0 : 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == slashCode) count += 1;
  }
  return count;
}

int staticCharCount(String path) {
  var count = 0;
  for (var i = 0; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) count += 1;
  }
  return count;
}
