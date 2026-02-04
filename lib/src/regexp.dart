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
        reSegments.add('?(?<${segment.substring(3)}>.+)');
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
