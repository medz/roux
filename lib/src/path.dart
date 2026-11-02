// ignore_for_file: public_member_api_docs

List<String> normalizedSegments(String path) {
  // One concrete list type lets AOT specialize the traversal, including at the root.
  if (path.isEmpty || path == '/') return <String>[];
  final segments = path.split('/');
  var used = 0;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final length = segment.length;
    if (length == 0) continue;
    if (length <= 2 &&
        segment.codeUnitAt(0) == 46 &&
        (length == 1 || segment.codeUnitAt(1) == 46)) {
      if (length == 2 && used > 0) used--;
    } else {
      segments[used++] = segment;
    }
  }
  return segments..length = used;
}
