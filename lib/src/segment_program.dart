// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

typedef CaptureGroup = ({String key, String name, int? index});
typedef _Run = ({Object atom, int min, int? max});
typedef _Span = ({int start, int end});

final _alphabet = String.fromCharCodes(List.generate(128, (i) => i));
final _token = RegExp(
  r'\(\?<([\w$]+)>|\(\?:|\)|'
  r'((?:[a-zA-Z0-9_-](?![?+*{]))+)|'
  r'(\[(?:\\[\s\S]|[^\]\\])*\]|\\[dDwWsS\\.^$*+?()[\]{}|/\-]|[^\\()[\]{}?+*|^$])'
  r'([*+?]|\{([0-9]{1,8})(?:,([0-9]{0,8}))?\})?',
);

Uint8List _charSet(String atom, bool sensitive) {
  final chars = Uint8List(128);
  final regexp = RegExp('(?:$atom)+', caseSensitive: sensitive);
  for (final m in regexp.allMatches(_alphabet)) {
    chars.fillRange(m.start, m.end, 1);
  }
  return chars;
}

final _classes = {
  for (final atom in [r'\d', r'\D', r'\w', r'\W', r'\s', r'\S', '.'])
    atom: _charSet(atom, true),
};

class SegmentProgram {
  SegmentProgram._(this._runs, this._spans, this.fixedLength);
  final List<_Run> _runs;
  final List<(String, _Span)> _spans;
  String get prefix => switch (_runs.firstOrNull?.atom) {
    final String text => text,
    _ => '',
  };
  final int? fixedLength;
  late final _needsOffsets = _spans.any(
    (s) => s.$2.start != 0 || s.$2.end != _runs.length,
  );

  static SegmentProgram? compile(
    String source,
    bool sensitive,
    List<CaptureGroup> captures,
  ) {
    final runs = <_Run>[];
    final stack = <(String?, int)>[];
    final bounds = <String, _Span>{};
    int? fixedLength = 0;
    String? previousVariable;
    var cursor = 0;
    for (final token in _token.allMatches(source)) {
      if (token.start != cursor) return null;
      cursor = token.end;
      final text = token[2];
      final atom = token[3];
      if (atom == null && text == null) {
        if (token[0] == ')') {
          if (stack.isEmpty) return null;
          final (name, start) = stack.removeLast();
          if (name != null) bounds[name] = (start: start, end: runs.length);
        } else {
          stack.add((token[1], runs.length));
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
      // A greedy run can commit when the next mandatory atom cannot consume its characters.
      if (previousVariable != null) {
        final next = text == null ? atom! : text[0];
        final overlap = RegExp(
          '(?=$previousVariable)$next',
          caseSensitive: sensitive,
        );
        if (min == 0 || overlap.hasMatch(_alphabet)) return null;
      }
      previousVariable = min == max ? null : atom;
      final step = text ?? _classes[atom] ?? _charSet(atom!, sensitive);
      if (fixedLength != null) {
        fixedLength = min == max ? fixedLength + min : null;
      }
      runs.add((atom: step, min: min, max: max));
    }
    if (cursor != source.length || stack.isNotEmpty) return null;
    final spans = [
      for (final group in captures) (group.key, bounds[group.name]!),
    ];
    return SegmentProgram._(runs, spans, fixedLength);
  }

  bool? capture(String value, Map<String, String> captures) {
    final ends = _needsOffsets ? List<int>.filled(_runs.length + 1, 0) : null;
    var pos = 0;
    for (var i = 0; i < _runs.length; i++) {
      final run = _runs[i];
      final atom = run.atom;
      if (atom is String) {
        if (!value.startsWith(atom, pos)) return null;
        pos += atom.length;
        ends?[i + 1] = pos;
        continue;
      }
      final start = pos;
      final chars = atom as Uint8List;
      final max = run.max;
      final limit = max == null || start + max > value.length
          ? value.length
          : start + max;
      while (pos < limit) {
        final c = value.codeUnitAt(pos);
        // Non-ASCII case folding and character classes use Dart's RegExp.
        if (c >= chars.length) return null;
        if (chars[c] == 0) break;
        pos++;
      }
      if (pos - start < run.min) return false;
      ends?[i + 1] = pos;
    }
    if (pos != value.length) return false;
    for (final (key, span) in _spans) {
      captures[key] = ends == null
          ? value
          : value.substring(ends[span.start], ends[span.end]);
    }
    return true;
  }
}
