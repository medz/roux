import 'dart:typed_data';

import 'route_model.dart';

@pragma('vm:prefer-inline')
int _classifyPathSegment(String path, int segmentStart, int segmentEnd) {
  final segmentLength = segmentEnd - segmentStart;
  if (segmentLength == 0) return 0;
  if (segmentLength == 1 && path.codeUnitAt(segmentStart) == 46) return 1;
  if (segmentLength == 2 &&
      path.codeUnitAt(segmentStart) == 46 &&
      path.codeUnitAt(segmentStart + 1) == 46) {
    return 2;
  }
  return -1;
}

/// Normalizes a path for exact-route lookup and returns `null` if invalid.
String? normalizeExactRoutePath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
  if (path.length == 1) return path;
  final out = Uint16List(path.length);
  var outStart = path.length, skip = 0, read = path.length - 1;
  while (read >= 0 && path.codeUnitAt(read) == slashCode) {
    read -= 1;
  }
  while (read >= 0) {
    final segmentEnd = read + 1;
    while (read >= 0 && path.codeUnitAt(read) != slashCode) {
      read -= 1;
    }
    final segmentStart = read + 1;
    switch (_classifyPathSegment(path, segmentStart, segmentEnd)) {
      case 0:
      case 1:
        read -= 1;
        continue;
      case 2:
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

/// Produces normalized segment spans in reverse order and returns their length.
int normalizePathSpans(String path, Uint32List spans) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return -1;
  if (path.length == 1) return 0;
  var length = 0, skip = 0, read = path.length - 1;
  while (read >= 0 && path.codeUnitAt(read) == slashCode) {
    read -= 1;
  }
  while (read >= 0) {
    final segmentEnd = read + 1;
    while (read >= 0 && path.codeUnitAt(read) != slashCode) {
      read -= 1;
    }
    final segmentStart = read + 1;
    switch (_classifyPathSegment(path, segmentStart, segmentEnd)) {
      case 0:
      case 1:
        read -= 1;
        continue;
      case 2:
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

/// Normalizes an input path while preserving the original casing.
String? normalizeRoutePath(String path) {
  if (!path.startsWith('/')) return null;
  if (path.length == 1) return path;
  var segmentStart = 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) continue;
    if (_classifyPathSegment(path, segmentStart, i) >= 0) {
      return normalizeExactRoutePath(path);
    }
    segmentStart = i + 1;
  }
  switch (_classifyPathSegment(path, segmentStart, path.length)) {
    case 0:
      return path.substring(0, path.length - 1);
    case 1:
    case 2:
      return normalizeExactRoutePath(path);
  }
  return path;
}

/// Ensures the reusable normalized span buffer can hold a given path.
Uint32List ensureSpanBuffer(Uint32List buffer, int pathLength) =>
    buffer.length >= pathLength * 2 ? buffer : Uint32List(pathLength * 2);

/// Reconstructs a normalized path from reverse-ordered segment spans.
String normalizedPathFromSpans(String path, List<int> spans, int spanLength) {
  if (spanLength == 0) return '/';
  var length = spanLength >> 1;
  for (var i = 0; i < spanLength; i += 2) {
    length += spans[i + 1] - spans[i];
  }
  final out = Uint16List(length);
  var write = 0;
  for (var pair = spanLength - 2; pair >= 0; pair -= 2) {
    out[write++] = slashCode;
    final start = spans[pair];
    final end = spans[pair + 1];
    for (var i = start; i < end; i++) {
      out[write++] = path.codeUnitAt(i);
    }
  }
  return String.fromCharCodes(out);
}

/// Removes a single trailing slash from a non-root path.
String trimTrailingSlash(String path) =>
    path.length > 1 && path.endsWith('/') && !path.endsWith('//')
    ? path.substring(0, path.length - 1)
    : path;

/// Canonicalizes a path key according to case-sensitivity settings.
String canonicalizeRoutePath(String path, bool caseSensitive) =>
    caseSensitive ? path : path.toLowerCase();

/// Finds the exclusive end offset of the segment starting at [start].
int findSegmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != slashCode) {
    i += 1;
  }
  return i;
}

/// Reports whether a path contains consecutive slash separators.
bool containsEmptySegments(String path) {
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i - 1) == slashCode &&
        path.codeUnitAt(i) == slashCode) {
      return true;
    }
  }
  return false;
}

/// Counts slash-delimited segments in a path.
int segmentCount(String path) {
  var count = path.length == 1 ? 0 : 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == slashCode) count += 1;
  }
  return count;
}

/// Counts non-slash characters in a path.
int staticCharCount(String path) {
  var count = 0;
  for (var i = 0; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) count += 1;
  }
  return count;
}
