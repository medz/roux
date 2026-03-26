import 'package:roux/roux.dart';

void main() {
  final router = Router<String>();
  router.add('/', 'root');
  router.add('/users/all', 'usersAll');
  router.add('/users/:id', 'userDetail');
  router.add('/users/*', 'usersWildcard');
  router.add('/**', 'globalFallback');

  describe(router, '/');
  describe(router, '/users/all');
  describe(router, '/users/42');
  describe(router, '/users/42/profile');
  describe(router, '/unknown/path');
}

void describe(Router<String> router, String path) {
  final match = router.find(path);
  if (match == null) {
    print('$path -> no match');
    return;
  }
  print('$path -> ${match.data} params=${match.params}');
}
