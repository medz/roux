import 'package:roux/roux.dart';

RouterContext<String> createTestRouter(List<String> routes) {
  final router = createRouter<String>();
  for (final route in routes) {
    addRoute(router, 'GET', route, route);
  }
  return router;
}
