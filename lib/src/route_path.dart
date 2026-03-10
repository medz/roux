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
  final spans = <int>[];
  var cursor = 1;
  while (cursor < path.length) {
    while (cursor < path.length && path.codeUnitAt(cursor) == slashCode) {
      cursor += 1;
    }
    if (cursor >= path.length) break;
    final segmentEnd = findSegmentEnd(path, cursor);
    final segmentLength = segmentEnd - cursor;
    if (segmentLength == 1 && path.codeUnitAt(cursor) == 46) {
      cursor = segmentEnd + 1;
      continue;
    }
    if (segmentLength == 2 &&
        path.codeUnitAt(cursor) == 46 &&
        path.codeUnitAt(cursor + 1) == 46) {
      if (spans.isEmpty) return null;
      spans.length -= 2;
      cursor = segmentEnd + 1;
      continue;
    }
    spans
      ..add(cursor)
      ..add(segmentEnd);
    cursor = segmentEnd + 1;
  }
  if (spans.isEmpty) return '/';
  final out = List<int>.filled(path.length, 0, growable: false);
  var outLength = 0;
  for (var i = 0; i < spans.length; i += 2) {
    out[outLength++] = slashCode;
    for (var j = spans[i]; j < spans[i + 1]; j++) {
      out[outLength++] = path.codeUnitAt(j);
    }
  }
  return String.fromCharCodes(out, 0, outLength);
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
