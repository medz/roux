// ignore_for_file: public_member_api_docs

List<String> normalizedSegments(String path) {
  // One concrete list type lets AOT specialize the traversal, including at the root.
  if (path.isEmpty || path == '/') return <String>[];
  final segments = path.split('/');
  var used = 0;
  for (final segment in segments) {
    if (segment.isEmpty) continue;
    if (segment.codeUnitAt(0) == 46 /* . */ ) {
      if (segment == '.') continue;
      if (segment == '..') {
        if (used > 0) used--;
        continue;
      }
    }
    segments[used++] = segment;
  }
  return segments..length = used;
}

/// Splits a path into segments, dropping the leading slash and any trailing empty segment.
List<String> splitPath(String path) {
  final segments = path.split('/')..removeAt(0);
  if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
  return segments;
}
