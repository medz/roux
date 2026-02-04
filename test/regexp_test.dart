import 'package:test/test.dart';
import 'package:roux/roux.dart';

class _MatchCase {
  final String path;
  final Map<String, String>? params;

  const _MatchCase(this.path, [this.params]);
}

class _RouteCase {
  final String route;
  final String pattern;
  final List<_MatchCase> matches;

  const _RouteCase(this.route, this.pattern, this.matches);
}

void main() {
  group('routeToRegExp', () {
    final cases = <_RouteCase>[
      _RouteCase('/path', r'^/path/?$', const [
        _MatchCase('/path'),
        _MatchCase('/path/'),
      ]),
      _RouteCase('/path/:param', r'^/path/(?<param>[^/]+)/?$', const [
        _MatchCase('/path/value', {'param': 'value'}),
        _MatchCase('/path/value/', {'param': 'value'}),
      ]),
      _RouteCase(
        '/path/get-:file.:ext',
        r'^/path/get-(?<file>[^/]+)\.(?<ext>[^/]+)/?$',
        const [
          _MatchCase('/path/get-file.txt', {'file': 'file', 'ext': 'txt'}),
        ],
      ),
      _RouteCase(
        '/path/:param1/:param2',
        r'^/path/(?<param1>[^/]+)/(?<param2>[^/]+)/?$',
        const [
          _MatchCase('/path/value1/value2', {
            'param1': 'value1',
            'param2': 'value2',
          }),
        ],
      ),
      _RouteCase('/path/*/foo', r'^/path/(?<_0>[^/]*)/foo/?$', const [
        _MatchCase('/path/anything/foo', {'_0': 'anything'}),
        _MatchCase('/path//foo', {'_0': ''}),
        _MatchCase('/path//foo/', {'_0': ''}),
      ]),
      _RouteCase('/path/**', r'^/path/?(?<_>.*)/?$', const [
        _MatchCase('/path/', {'_': ''}),
        _MatchCase('/path', {'_': ''}),
        _MatchCase('/path/anything/more', {'_': 'anything/more'}),
      ]),
      _RouteCase('/base/**:path', r'^/base/?(?<path>.+)/?$', const [
        _MatchCase('/base/anything/more', {'path': 'anything/more'}),
      ]),
      _RouteCase(
        r'/static%3Apath/\*/\*\*',
        r'^/static%3Apath/\*/\*\*/?$',
        const [_MatchCase('/static%3Apath/*/**')],
      ),
      _RouteCase('/**', r'^/?(?<_>.*)/?$', const [
        _MatchCase('/', {'_': ''}),
        _MatchCase('/anything', {'_': 'anything'}),
        _MatchCase('/any/deep/path', {'_': 'any/deep/path'}),
      ]),
    ];

    for (final testCase in cases) {
      test('route "${testCase.route}" => ${testCase.pattern}', () {
        final router = createRouter<String>();
        addRoute(router, 'GET', testCase.route, testCase.route);

        final regex = routeToRegExp(testCase.route);
        expect(regex.pattern, testCase.pattern);

        for (final matchCase in testCase.matches) {
          final match = findRoute(router, 'GET', matchCase.path);
          expect(match, isNotNull, reason: matchCase.path);
          expect(match?.data, testCase.route);

          if (matchCase.params != null) {
            expect(match?.params, matchCase.params);
          }

          final regexMatch = regex.firstMatch(matchCase.path);
          expect(regexMatch, isNotNull, reason: matchCase.path);

          if (matchCase.params != null) {
            final actualParams = <String, String>{};
            for (final entry in matchCase.params!.entries) {
              actualParams[entry.key] = regexMatch!.namedGroup(entry.key)!;
            }
            expect(actualParams, matchCase.params);
          }
        }
      });
    }
  });
}
