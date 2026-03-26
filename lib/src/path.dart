// Path normalization utilities for roux.
// ignore_for_file: public_member_api_docs

const int slashCode = 47;

int _segClass(String path, int s, int e) {
  final len = e - s;
  if (len == 0) return 0;
  if (len == 1 && path.codeUnitAt(s) == 46) return 1;
  if (len == 2 && path.codeUnitAt(s) == 46 && path.codeUnitAt(s + 1) == 46) {
    return 2;
  }
  return -1;
}

/// Normalizes a path, resolving `..`, `.`, `//`.
/// Returns null if the path is invalid or escapes root.
String? normalizeExact(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
  if (path.length == 1) return path;
  final out = List<int>.filled(path.length, 0);
  var outStart = path.length, skip = 0, read = path.length - 1;
  while (read >= 0 && path.codeUnitAt(read) == slashCode) {
    read--;
  }
  while (read >= 0) {
    final e = read + 1;
    while (read >= 0 && path.codeUnitAt(read) != slashCode) {
      read--;
    }
    final s = read + 1;
    switch (_segClass(path, s, e)) {
      case 0:
      case 1:
        read--;
        continue;
      case 2:
        skip++;
        read--;
        continue;
    }
    if (skip > 0) {
      skip--;
      read--;
      continue;
    }
    for (var i = e - 1; i >= s; i--) {
      out[--outStart] = path.codeUnitAt(i);
    }
    out[--outStart] = slashCode;
    read--;
  }
  if (skip > 0) return null;
  return outStart == path.length ? '/' : String.fromCharCodes(out, outStart);
}

/// Normalizes a route path (handles `..`, `.`, trailing slash), preserving case.
String? normalizeRoutePath(String path) {
  if (!path.startsWith('/')) return null;
  if (path.length == 1) return path;
  var s = 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) continue;
    if (_segClass(path, s, i) >= 0) return normalizeExact(path);
    s = i + 1;
  }
  return switch (_segClass(path, s, path.length)) {
    0 => path.substring(0, path.length - 1),
    1 || 2 => normalizeExact(path),
    _ => path,
  };
}

/// Removes a single trailing slash from a non-root path.
String trimTrailingSlash(String path) =>
    path.length > 1 && path.endsWith('/') && !path.endsWith('//')
    ? path.substring(0, path.length - 1)
    : path;

/// Returns true if the path has consecutive slashes.
bool hasEmptySegments(String path) {
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i - 1) == slashCode &&
        path.codeUnitAt(i) == slashCode) {
      return true;
    }
  }
  return false;
}

/// Returns the exclusive end offset of the segment starting at [start].
int findSegmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != slashCode) {
    i++;
  }
  return i;
}

/// Counts non-slash characters in [path].
int countStaticChars(String path) {
  var n = 0;
  for (var i = 0; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) n++;
  }
  return n;
}

/// Counts slash-delimited segments in [path].
int countSegments(String path) {
  if (path.length == 1) return 0;
  var n = 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == slashCode) n++;
  }
  return n;
}
