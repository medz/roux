# Registration and memory study

Measured against Roux 2.0.0 on macOS arm64 with Dart 3.13.7. Each timing is the median across five fresh AOT processes run in alternating order. Each process builds a table of 4,096 pregenerated routes once for warmup and seven more times for measurement. Three handler lookups validate each table outside the timer.

The retained column measures the router’s exclusive object graph after a forced GC at 8,192 routes. Peak RSS includes the process, allocator, and incrementally generated inputs during a fresh build of 32,768 routes. Lower is better. Each pair shows 2.0.0 → this branch.

| Workload | Registration (ns/add) | Retained (bytes/route) | Peak RSS (MiB) |
| --- | ---: | ---: | ---: |
| static | 680.6 → 224.0 | 360.0 → 200.0 | 36.92 → 25.78 |
| params | 1423.6 → 716.1 | 920.0 → 648.0 | 63.53 → 62.20 |
| wildcard | 882.0 → 419.7 | 536.0 → 376.0 | 60.31 → 44.73 |
| nested | 14311.9 → 9924.4 | 1576.0 → 904.0 | 95.36 → 74.11 |
| indexed | 3292.7 → 2853.5 | 954.5 → 650.1 | 74.64 → 67.22 |
| methods | 677.1 → 234.2 | 302.0 → 166.0 | 40.97 → 25.30 |
| optional | 2209.0 → 1365.2 | 792.0 → 424.0 | 69.41 → 58.41 |

## Other routers

Same handler and route shapes for all three libraries. Shelf pattern conversion and Relic cache resets take place outside the timer. Shelf registers HEAD alongside GET. The exclusive retained size excludes objects held by Relic’s global cache. The NoCache column uses a fresh table without that cache.

| Workload | Metric | Roux branch | Relic 1.2.0 | Relic NoCache | shelf_router 1.1.5 |
| --- | --- | ---: | ---: | ---: | ---: |
| static | ns/add | 233.9 | 553.3 | 473.9 | 1567.6 |
| static | bytes/route | 200.0 | 232.1 | 264.0 | 632.0 |
| params | ns/add | 725.2 | 983.8 | 858.0 | 3556.6 |
| params | bytes/route | 648.0 | 1128.1 | 1224.0 | 1240.0 |
| methods | ns/add | 231.5 | 252.0 | 402.6 | 995.4 |
| methods | bytes/route | 166.0 | 58.1 | 66.0 | 298.0 |

## Lookup and behavior

The unchanged public lookup suite has 13 workloads. Nested regex latency was 207.1 → 184.6 ns. The wider AOT matrix covered 60 lookup, dispatch, cold-access and removal measurements, plus the 13 public lookup workloads under both JIT and dart2js/Node. Both the VM and JavaScript agreed with the release on 833,953 differential checks.

Raw medians were higher for captures/no-prefix-last 215.4 → 216.1 ns, extra/mixed-case method 209.6 → 211.1 ns.

Paired follow-up measurements added six process pairs per flagged AOT suite and two per flagged JIT or JavaScript suite. All original samples are included.

| Runtime and workload | Process pairs | Combined ns, baseline → branch | Median paired difference (ns) |
| --- | ---: | ---: | ---: |
| captures / no-prefix-last | 11 | 216.3 → 216.7 | -0.2 |
| extra / mixed-case method | 11 | 207.9 → 211.1 | +2.5 |

## Reproduce Roux measurements

Run the same commands on both revisions with the same benchmark files and Dart SDK. Use a freshly launched process for each RSS sample. The retained-heap command uses the Dart VM service’s diagnostic retained-size RPC.

```sh
dart pub get
dart compile exe benchmark/registration.dart -o /tmp/roux-registration
/tmp/roux-registration params 4096
/tmp/roux-registration params 32768 rss
dart run --enable-vm-service=0/127.0.0.1 --no-dds benchmark/retained.dart params 8192
dart compile exe benchmark/lookup.dart -o /tmp/roux-lookup
/tmp/roux-lookup
```
