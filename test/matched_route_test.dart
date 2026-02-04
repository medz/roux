import 'package:test/test.dart';
import 'package:roux/roux.dart';

void main() {
  group('MatchedRoute equality', () {
    test('compares data and params by value', () {
      expect(
        MatchedRoute('user', {'id': '123'}),
        equals(MatchedRoute('user', {'id': '123'})),
      );
    });

    test('treats param map order as irrelevant', () {
      final a = MatchedRoute('user', {'a': '1', 'b': '2'});
      final b = MatchedRoute('user', {'b': '2', 'a': '1'});
      expect(a, equals(b));
    });

    test('distinguishes different data or params', () {
      expect(
        MatchedRoute('user', {'id': '123'}),
        isNot(equals(MatchedRoute('user', {'id': '124'}))),
      );
      expect(
        MatchedRoute('user', {'id': '123'}),
        isNot(equals(MatchedRoute('admin', {'id': '123'}))),
      );
    });

    test('handles null params', () {
      expect(MatchedRoute('user'), equals(MatchedRoute('user')));
      expect(
        MatchedRoute('user'),
        isNot(equals(MatchedRoute('user', {'id': '123'}))),
      );
    });

    test('hashCode is consistent with equality', () {
      final a = MatchedRoute('user', {'id': '123'});
      final b = MatchedRoute('user', {'id': '123'});
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
