import 'package:roux/roux.dart';

void main() {
  final router = createRouter<String>(caseSensitive: false);

  addRoute(router, 'GET', '/users', 'listUsers');
  addRoute(router, 'GET', '/users/:id', 'getUser');
  addRoute(router, 'GET', '/files/:name.:ext', 'getFile');
  addRoute(router, null, '/health', 'healthCheck');
  addRoute(router, 'GET', '/assets/**:path', 'assetLookup');
  addRoute(router, 'GET', '/docs/*', 'docsWildcard');

  describe(router, 'GET', '/users');
  describe(router, 'GET', '/users/42');
  describe(router, 'GET', '/files/report.pdf');
  describe(router, 'POST', '/health');
  describe(router, 'GET', '/assets/images/logo.png');
  describe(router, 'GET', '/docs/getting-started');
  describe(router, 'GET', '/missing');
}

void describe(RouterContext<String> router, String? method, String path) {
  final match = findRoute(router, method, path);
  if (match == null) {
    print('[${method ?? 'ANY'}] $path -> no match');
    return;
  }

  final params = match.params == null ? '' : ' params=${match.params}';
  print('[${method ?? 'ANY'}] $path -> ${match.data}$params');
}
