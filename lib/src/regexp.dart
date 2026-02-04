/// Converts a route pattern to a [RegExp] with named captures.
///
/// The returned regex is anchored and allows an optional trailing slash.
/// Named params become named capture groups; `*` and `**` use `_0`, `_1`, ...
/// and `_` respectively.
RegExp routeToRegExp([String route = '/']) {
  final reSegments = <String>[];
  var idCtr = 0;

  for (final segment in route.split('/')) {
    if (segment.isEmpty) {
      continue;
    }
    if (segment == '*') {
      reSegments.add('(?<_${idCtr++}>[^/]*)');
      continue;
    }
    if (segment.startsWith('**')) {
      if (segment == '**') {
        reSegments.add('?(?<_>.*)');
      } else {
        final name = segment.length > 3 ? segment.substring(3) : '';
        if (name.isEmpty) {
          reSegments.add('?(?<_>.*)');
        } else {
          reSegments.add('?(?<$name>.+)');
        }
      }
      continue;
    }
    if (segment.contains(':')) {
      reSegments.add(
        segment
            .replaceAllMapped(
              RegExp(r':(\w+)'),
              (match) => '(?<${match.group(1)}>[^/]+)',
            )
            .replaceAll('.', r'\.'),
      );
      continue;
    }
    reSegments.add(segment);
  }

  return RegExp('^/${reSegments.join('/')}/?\$');
}
