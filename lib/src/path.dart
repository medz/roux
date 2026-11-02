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

// Zero needs parsing. The sign distinguishes literal paths from paths with named parameters.
int canonicalDepth(String path) {
  if (path.isEmpty || path.codeUnitAt(0) != 47 || path.length == 1) return 0;
  var depth = 1, start = 1, named = false;
  for (var i = 1; i < path.length; i++) {
    final c = path.codeUnitAt(i);
    if (c == 47) {
      if (i == start || i + 1 == path.length) return 0;
      depth++;
      start = i + 1;
    } else if (_isPatternUnit(c)) {
      if (c != 58 || i != start) return 0;
      final end = _nameEnd(path, i + 1);
      if (end == i + 1 || end < path.length && path.codeUnitAt(end) != 47) {
        return 0;
      }
      named = true;
      i = end - 1;
    } else if (c == 46 &&
        i == start &&
        (i + 1 == path.length ||
            path.codeUnitAt(i + 1) == 47 ||
            path.codeUnitAt(i + 1) == 46 &&
                (i + 2 == path.length || path.codeUnitAt(i + 2) == 47))) {
      return 0;
    }
  }
  return named ? -depth : depth;
}

int _nameEnd(String text, int start) {
  var i = start;
  for (; i < text.length; i++) {
    final c = text.codeUnitAt(i), lower = c | 32;
    if (lower >= 97 && lower <= 122 || c == 95) continue;
    if (i == start || c != 45 && (c < 48 || c > 57)) break;
  }
  return i;
}

bool isName(String text, [int start = 0]) =>
    start < text.length && _nameEnd(text, start) == text.length;
// A backslash and the internal escape marker also require the pattern parser.
bool _isPatternUnit(int unit) =>
    unit == 58 ||
    unit == 42 ||
    unit == 40 ||
    unit == 123 ||
    unit == 92 ||
    unit == 0xfffd;

String literalCase(String value, bool sensitive) =>
    sensitive ? value : value.toLowerCase();

bool isPlainSegment(String key) {
  if (key.isEmpty || key == '.' || key == '..') return false;
  for (var i = 0; i < key.length; i++) {
    final c = key.codeUnitAt(i);
    if (c == 47 || _isPatternUnit(c)) return false;
  }
  return true;
}
