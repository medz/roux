import 'route_entry.dart';

String? normalizeInputPath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
  final last = path.length - 1;
  if (path.length > 1 && path.codeUnitAt(last) == slashCode) {
    if (path.codeUnitAt(last - 1) == slashCode) return null;
    path = path.substring(0, last);
  }
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i - 1) == slashCode &&
        path.codeUnitAt(i) == slashCode) {
      return null;
    }
  }
  return path;
}

String? normalizePathInput(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != slashCode) return null;
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

int findSegmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != slashCode) {
    i += 1;
  }
  return i;
}

int pathDepth(String path) {
  var count = path.length == 1 ? 0 : 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == slashCode) count += 1;
  }
  return count;
}

int literalCharCount(String path) {
  var count = 0;
  for (var i = 0; i < path.length; i++) {
    if (path.codeUnitAt(i) != slashCode) count += 1;
  }
  return count;
}
