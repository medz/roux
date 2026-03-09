part of 'router.dart';

class _MatchCollector<T> {
  final bool _sortMatches;
  final List<RouteMatch<T>> _matches = <RouteMatch<T>>[];
  final List<_Route<T>> _routes = <_Route<T>>[];
  final List<int> _methodRanks = <int>[];
  _MatchCollector(this._sortMatches);

  void add(RouteMatch<T> match, _Route<T> route, int methodRank) {
    if (!_sortMatches) {
      _matches.add(match);
      return;
    }
    final index = _matches.length;
    if (index == 0 ||
        !_sortsBefore(
          route,
          methodRank,
          _routes[index - 1],
          _methodRanks[index - 1],
        )) {
      _matches.add(match);
      _routes.add(route);
      _methodRanks.add(methodRank);
      return;
    }
    _matches.add(match);
    _routes.add(route);
    _methodRanks.add(methodRank);
    var insertIndex = index;
    while (insertIndex > 0 &&
        _sortsBefore(
          route,
          methodRank,
          _routes[insertIndex - 1],
          _methodRanks[insertIndex - 1],
        )) {
      _matches[insertIndex] = _matches[insertIndex - 1];
      _routes[insertIndex] = _routes[insertIndex - 1];
      _methodRanks[insertIndex] = _methodRanks[insertIndex - 1];
      insertIndex -= 1;
    }
    _matches[insertIndex] = match;
    _routes[insertIndex] = route;
    _methodRanks[insertIndex] = methodRank;
  }

  List<RouteMatch<T>> finish() => _matches;
}

bool _sortsBefore<T>(
  _Route<T> a,
  int methodRankA,
  _Route<T> b,
  int methodRankB,
) {
  var diff = a.rankPrefix - b.rankPrefix;
  if (diff != 0) return diff < 0;
  diff = methodRankA - methodRankB;
  if (diff != 0) return diff < 0;
  return a.registrationOrder < b.registrationOrder;
}

bool _compiledSortsBefore<T>(_Route<T> a, _Route<T> b) {
  final diff = b.rankPrefix - a.rankPrefix;
  if (diff != 0) return diff < 0;
  return a.registrationOrder < b.registrationOrder;
}
