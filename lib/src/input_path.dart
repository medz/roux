part of 'router.dart';

String? _normalizeInputPath(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) return null;
  final last = path.length - 1;
  if (path.length > 1 && path.codeUnitAt(last) == _slashCode) {
    if (path.codeUnitAt(last - 1) == _slashCode) return null;
    path = path.substring(0, last);
  }
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i - 1) == _slashCode &&
        path.codeUnitAt(i) == _slashCode) {
      return null;
    }
  }
  return path;
}

String? _normalizePathInput(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != _slashCode) return null;
  final segments = <String>[];
  var cursor = 1;
  while (cursor < path.length) {
    while (cursor < path.length && path.codeUnitAt(cursor) == _slashCode) {
      cursor += 1;
    }
    if (cursor >= path.length) break;
    final segmentEnd = _findSegmentEnd(path, cursor);
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

int _findSegmentEnd(String path, int start) {
  var i = start;
  while (i < path.length && path.codeUnitAt(i) != _slashCode) {
    i += 1;
  }
  return i;
}

int _pathDepth(String path) {
  var count = path.length == 1 ? 0 : 1;
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) == _slashCode) count += 1;
  }
  return count;
}

int _literalCharCount(String path) {
  var count = 0;
  for (var i = 0; i < path.length; i++) {
    if (path.codeUnitAt(i) != _slashCode) count += 1;
  }
  return count;
}
