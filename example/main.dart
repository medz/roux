import 'package:roux/roux.dart';

void main() {
  final router = Router<String>(
    routes: {
      '/': 'root',
      '/users/all': 'usersAll',
      '/users/:id': 'userDetail',
      '/users/*': 'usersWildcard',
      '/*': 'globalFallback',
    },
  );

  describe(router, '/');
  describe(router, '/users/all');
  describe(router, '/users/42');
  describe(router, '/users/42/profile');
  describe(router, '/unknown/path');
}

void describe(Router<String> router, String path) {
  final match = router.match(path);
  if (match == null) {
    print('$path -> no match');
    return;
  }
  print('$path -> ${match.data} params=${match.params}');
}
