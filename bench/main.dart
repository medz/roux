import 'add_route_bench.dart';
import 'find_all_routes_bench.dart';
import 'find_route_bench.dart';
import 'remove_route_bench.dart';

void main() {
  FindRouteBench().report();
  FindAllRoutesBench().report();
  AddRouteBench().report();
  RemoveRouteBench().report();
}
