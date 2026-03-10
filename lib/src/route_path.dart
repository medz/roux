import 'route_model.dart';

String? sanitizeRoutePath(String path) {
  if (!path.startsWith('/')) return null;
  return trimTrailingSlash(path);
}

String? normalizeExactRoutePath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
  if (path.length == 1) return path;
  final out = List<int>.filled(path.length, 0, growable: false);
  var outStart = path.length;
  var skip = 0;
  var read = path.length - 1;
  while (read >= 0 && path.codeUnitAt(read) == slashCode) {
    read -= 1;
  }
  while (read >= 0) {
    final segmentEnd = read + 1;
    while (read >= 0 && path.codeUnitAt(read) != slashCode) {
      read -= 1;
    }
    final segmentStart = read + 1;
    final segmentLength = segmentEnd - segmentStart;
    if (segmentLength == 0) {
      read -= 1;
      continue;
    }
    if (segmentLength == 1 && path.codeUnitAt(segmentStart) == 46) {
      read -= 1;
      continue;
    }
    if (segmentLength == 2 &&
        path.codeUnitAt(segmentStart) == 46 &&
        path.codeUnitAt(segmentStart + 1) == 46) {
      skip += 1;
      read -= 1;
      continue;
    }
    if (skip > 0) {
      skip -= 1;
      read -= 1;
      continue;
    }
    for (var i = segmentEnd - 1; i >= segmentStart; i--) {
      out[--outStart] = path.codeUnitAt(i);
    }
    out[--outStart] = slashCode;
    read -= 1;
  }
  if (skip > 0) return null;
  return outStart == path.length ? '/' : String.fromCharCodes(out, outStart);
}

int normalizePathSpans(String path, List<int> spans) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return -1;
  if (path.length == 1) return 0;
  var length = 0;
  var skip = 0;
  var read = path.length - 1;
  while (read >= 0 && path.codeUnitAt(read) == slashCode) {
    read -= 1;
  }
  while (read >= 0) {
    final segmentEnd = read + 1;
    while (read >= 0 && path.codeUnitAt(read) != slashCode) {
      read -= 1;
    }
    final segmentStart = read + 1;
    final segmentLength = segmentEnd - segmentStart;
    if (segmentLength == 0) {
      read -= 1;
      continue;
    }
    if (segmentLength == 1 && path.codeUnitAt(segmentStart) == 46) {
      read -= 1;
      continue;
    }
    if (segmentLength == 2 &&
        path.codeUnitAt(segmentStart) == 46 &&
        path.codeUnitAt(segmentStart + 1) == 46) {
      skip += 1;
      read -= 1;
      continue;
    }
    if (skip > 0) {
      skip -= 1;
      read -= 1;
      continue;
    }
    spans[length++] = segmentStart;
    spans[length++] = segmentEnd;
    read -= 1;
  }
  if (skip > 0) return -1;
  return length;
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
  return normalizeExactRoutePath(path);
}

List<int> ensureSpanBuffer(List<int> buffer, int pathLength) =>
    buffer.length >= pathLength * 2
    ? buffer
    : List<int>.filled(pathLength * 2, 0, growable: false);

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
