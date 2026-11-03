// ignore_for_file: public_member_api_docs

import 'dart:math' show min;
import 'dart:typed_data';

const String unnamedGroupPrefix = '__roux_unnamed_';
String normalizeUnnamedGroupKey(String key) =>
    key.startsWith(unnamedGroupPrefix)
    ? key.substring(unnamedGroupPrefix.length)
    : key;

class CaptureGroup {
  CaptureGroup(this.name, this.index) : key = normalizeUnnamedGroupKey(name);
  final String key;
  final String name;
  int? index;
  int start = 0;
  int end = 0;
}

typedef _Run = ({Object atom, int min, int? max});

final _alphabet = String.fromCharCodes(List.generate(128, (i) => i));
final _token = RegExp(
  r'\(\?<([\w$]+)>|\(\?:|\)|'
  r'((?:[a-zA-Z0-9_-](?![?+*{]))+)|'
  r'(\[(?:\\[\s\S]|[^\]\\])*\]|\\[dDwWsS\\.^$*+?()[\]{}|/\-]|[^\\()[\]{}?+*|^$])'
  r'([*+?]|\{([0-9]{1,8})(?:,([0-9]{0,8}))?\})?',
);

Uint8List _charSet(String atom, bool sensitive) {
  final chars = Uint8List(16);
  final regexp = RegExp('(?:$atom)+', caseSensitive: sensitive);
  for (final m in regexp.allMatches(_alphabet)) {
    for (var c = m.start; c < m.end; c++) {
      chars[c >> 3] |= 1 << (c & 7);
    }
  }
  return chars;
}

bool _allows(Uint8List bits, int code) =>
    bits[code >> 3] & (1 << (code & 7)) != 0;

bool _overlaps(Uint8List left, Object right) {
  if (right is String) return _allows(left, right.codeUnitAt(0));
  return (right as Uint8List).indexed.any(
    (byte) => (left[byte.$1] & byte.$2) != 0,
  );
}

final _classes = {
  for (final atom in [r'\d', r'\D', r'\w', r'\W', r'\s', r'\S', '.'])
    atom: _charSet(atom, true),
};

final _literalPrefix = RegExp(r'^[a-zA-Z0-9_-]+(?=$|\\|\[|\()');

class SegmentPattern {
  SegmentPattern(
    String source,
    String head,
    bool sensitive,
    List<CaptureGroup> captures,
    this.separator,
  ) : groups = captures.toList(growable: false),
      regex = RegExp('^$source\$', caseSensitive: sensitive) {
    if (separator == null) _compile(source, sensitive);
    final atom = _runs?.firstOrNull?.atom;
    prefix = atom is String
        ? atom
        : _runs == null && !head.contains('|')
        ? _literalPrefix.stringMatch(head) ?? ''
        : '';
  }

  final RegExp regex;
  final List<CaptureGroup> groups;
  final String? separator;
  late final String prefix;
  int? fixedLength;
  List<_Run>? _runs;
  late final _needsOffsets = groups.any(
    (g) => g.start != 0 || g.end != _runs!.length,
  );

  void _compile(String source, bool sensitive) {
    final runs = <_Run>[];
    final stack = <CaptureGroup?>[];
    final byName = {for (final group in groups) group.name: group};
    int? fixedLength = 0;
    Uint8List? previousVariable;
    var cursor = 0;
    for (final token in _token.allMatches(source)) {
      if (token.start != cursor) return;
      cursor = token.end;
      final text = token[2];
      final atom = token[3];
      if (atom == null && text == null) {
        if (token[0] == ')') {
          if (stack.isEmpty) return;
          stack.removeLast()?.end = runs.length;
        } else {
          final group = byName[token[1]];
          group?.start = runs.length;
          stack.add(group);
        }
        continue;
      }
      final quantifier = token[4];
      final min = switch (quantifier) {
        '?' || '*' => 0,
        _ => text?.length ?? (token[5] == null ? 1 : int.parse(token[5]!)),
      };
      final max = switch (quantifier) {
        '*' || '+' => null,
        '?' => 1,
        _ => token[6] == null ? min : int.tryParse(token[6]!),
      };
      final step = text ?? _classes[atom] ?? _charSet(atom!, sensitive);
      // A greedy run is safe when the next mandatory atom accepts disjoint characters.
      if (previousVariable != null &&
          (min == 0 || _overlaps(previousVariable, step))) {
        return;
      }
      previousVariable = min == max ? null : step as Uint8List;
      if (fixedLength != null) {
        fixedLength = min == max ? fixedLength + min : null;
      }
      runs.add((atom: step, min: min, max: max));
    }
    if (cursor != source.length || stack.isNotEmpty) return;
    _runs = runs.toList(growable: false);
    this.fixedLength = fixedLength;
  }

  bool capture(String value, Map<String, String> captures) {
    final runs = _runs;
    if (runs != null) {
      final match = _captureRuns(runs, value, captures);
      if (match != null) return match;
    }
    if (groups.length == 1 && groups.first.index == 0) {
      if (!regex.hasMatch(value)) return false;
      captures[groups.first.key] = value;
      return true;
    }
    if (separator case final sep?) {
      final end = value.length - sep.length - 1;
      if (end < 1) return false;
      // The first capture is greedy and the second must be nonempty.
      final cut = value.lastIndexOf(sep, end);
      if (cut < 1) return false;
      captures[groups.first.key] = value.substring(0, cut);
      captures[groups.last.key] = value.substring(cut + sep.length);
      return true;
    }
    final match = regex.firstMatch(value);
    if (match == null) return false;
    for (final group in groups) {
      final part = group.index == 0
          ? value
          : group.index == null
          ? match.namedGroup(group.name)
          : match[group.index!];
      if (part != null) captures[group.key] = part;
    }
    return true;
  }

  bool? _captureRuns(
    List<_Run> runs,
    String value,
    Map<String, String> captures,
  ) {
    final ends = _needsOffsets ? List<int>.filled(runs.length + 1, 0) : null;
    var pos = 0;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final atom = run.atom;
      if (atom is String) {
        if (!value.startsWith(atom, pos)) return null;
        pos += atom.length;
      } else {
        final start = pos;
        final chars = atom as Uint8List;
        final limit =
            start + min(value.length - start, run.max ?? value.length);
        while (pos < limit) {
          final c = value.codeUnitAt(pos);
          // Non-ASCII case folding and character classes use Dart's RegExp.
          if (c >= 128) return null;
          if (!_allows(chars, c)) break;
          pos++;
        }
        if (pos - start < run.min) return false;
      }
      ends?[i + 1] = pos;
    }
    if (pos != value.length) return false;
    for (final group in groups) {
      captures[group.key] = ends == null
          ? value
          : value.substring(ends[group.start], ends[group.end]);
    }
    return true;
  }
}
