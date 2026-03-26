// ignore_for_file: public_member_api_docs

const int slashCode = 47;

String normalizePath(String path) {
  if (path.isEmpty) return '/';
  if (path.codeUnitAt(0) != slashCode) path = '/$path';
  if (path.length == 1) return path;

  var start = 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) continue;
    if (_segmentKind(path, start, i) >= 0) return _normalizeTail(path);
    start = i + 1;
  }

  final tail = _segmentKind(path, start, path.length);
  return tail == 0
      ? path.substring(0, path.length - 1)
      : tail > 0
      ? _normalizeTail(path)
      : path;
}

String canonicalizeRoutePath(String path) {
  if (path.isEmpty) return '/';
  if (path.codeUnitAt(0) != slashCode) path = '/$path';
  while (path.length > 1 && path.codeUnitAt(path.length - 1) == slashCode) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// Splits a path into segments, dropping the leading slash and any trailing empty segment.
List<String> splitPath(String path) {
  if (path == '/') return const [];
  final segments = path.split('/').sublist(1);
  return segments.isNotEmpty && segments.last.isEmpty
      ? segments.sublist(0, segments.length - 1)
      : segments;
}

int _segmentKind(String path, int start, int end) {
  final len = end - start;
  if (len == 0) return 0;
  if (len == 1 && path.codeUnitAt(start) == 46) return 1;
  return len == 2 &&
          path.codeUnitAt(start) == 46 &&
          path.codeUnitAt(start + 1) == 46
      ? 2
      : -1;
}

String _normalizeTail(String path) {
  final kept = <String>[];
  for (var read = path.length - 1, skip = 0; read >= 0; read--) {
    while (read >= 0 && path.codeUnitAt(read) == slashCode) {
      read--;
    }
    if (read < 0) break;
    final segmentEnd = read + 1;
    while (read >= 0 && path.codeUnitAt(read) != slashCode) {
      read--;
    }
    final segmentStart = read + 1;
    switch (_segmentKind(path, segmentStart, segmentEnd)) {
      case 0:
      case 1:
        continue;
      case 2:
        skip++;
        continue;
    }
    if (skip > 0) {
      skip--;
      continue;
    }
    kept.add(path.substring(segmentStart, segmentEnd));
  }
  return kept.isEmpty ? '/' : '/${kept.reversed.join('/')}';
}
