// ignore_for_file: public_member_api_docs

String normalizePath(String path) {
  if (path.isEmpty) return '/';
  if (path.codeUnitAt(0) != 47 /* / */ ) path = '/$path';
  if (path.length == 1) return path;

  final segments = <String>[];
  for (final segment in path.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      default:
        segments.add(segment);
    }
  }

  return segments.isEmpty ? '/' : '/${segments.join('/')}';
}

/// Splits a path into segments, dropping the leading slash and any trailing empty segment.
List<String> splitPath(String path) {
  if (path == '/') return const [];
  final segments = path.split('/').sublist(1);
  return segments.isNotEmpty && segments.last.isEmpty
      ? segments.sublist(0, segments.length - 1)
      : segments;
}
