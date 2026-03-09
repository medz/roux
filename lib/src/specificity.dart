import 'route_entry.dart';
import 'types.dart';

class MatchCollector<T> {
  final bool sortMatches;
  final List<RouteMatch<T>> matches = <RouteMatch<T>>[];
  final List<RouteEntry<T>> routes = <RouteEntry<T>>[];
  final List<int> methodRanks = <int>[];

  MatchCollector(this.sortMatches);

  void add(RouteMatch<T> match, RouteEntry<T> route, int methodRank) {
    if (!sortMatches) {
      matches.add(match);
      return;
    }
    final index = matches.length;
    if (index == 0 ||
        !sortsBefore(
          route,
          methodRank,
          routes[index - 1],
          methodRanks[index - 1],
        )) {
      matches.add(match);
      routes.add(route);
      methodRanks.add(methodRank);
      return;
    }
    matches.add(match);
    routes.add(route);
    methodRanks.add(methodRank);
    var insertIndex = index;
    while (insertIndex > 0 &&
        sortsBefore(
          route,
          methodRank,
          routes[insertIndex - 1],
          methodRanks[insertIndex - 1],
        )) {
      matches[insertIndex] = matches[insertIndex - 1];
      routes[insertIndex] = routes[insertIndex - 1];
      methodRanks[insertIndex] = methodRanks[insertIndex - 1];
      insertIndex -= 1;
    }
    matches[insertIndex] = match;
    routes[insertIndex] = route;
    methodRanks[insertIndex] = methodRank;
  }
}

bool sortsBefore<T>(
  RouteEntry<T> a,
  int methodRankA,
  RouteEntry<T> b,
  int methodRankB,
) {
  final rankDiff = a.rankPrefix - b.rankPrefix;
  if (rankDiff != 0) return rankDiff < 0;
  final methodDiff = methodRankA - methodRankB;
  if (methodDiff != 0) return methodDiff < 0;
  return a.registrationOrder < b.registrationOrder;
}

bool compiledSortsBefore<T>(RouteEntry<T> a, RouteEntry<T> b) {
  final diff = b.rankPrefix - a.rankPrefix;
  if (diff != 0) return diff < 0;
  return a.registrationOrder < b.registrationOrder;
}
