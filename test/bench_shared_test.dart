import 'package:test/test.dart';

import '../bench/_shared.dart';

void main() {
  group('bench shared helpers', () {
    test('parseIntArg rejects non-positive values', () {
      expect(() => parseIntArg(['roux', '0'], 1, 500), throwsArgumentError);
      expect(() => parseIntArg(['roux', '-1'], 1, 500), throwsArgumentError);
    });

    test('parseIntArg rejects invalid integers', () {
      expect(() => parseIntArg(['roux', 'abc'], 1, 500), throwsArgumentError);
    });

    test('parseIntArg still returns fallback when arg is omitted', () {
      expect(parseIntArg(['roux'], 1, 500), 500);
    });
  });
}
