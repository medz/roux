enum DuplicatePolicy { reject, replace, keepFirst, append }

class RouteMatch<T> {
  final T data;
  final Map<String, String>? params;

  RouteMatch(this.data, [this.params]);
}
