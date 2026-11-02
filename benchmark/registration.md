# Roux against Relic and shelf_router

macOS arm64, Dart 3.13.7, Relic Core 1.2.0 and shelf_router 1.1.5 with Shelf 1.4.3. Every multiplier divides the peer’s time or memory by Roux’s. A value of 2× means Roux used half as much. A value below 1× means the peer won.

Of 94 peer comparisons, 24 reached 10×, 69 reached parity but fell short of 10×, and 1 fell below parity. Roux exceeded the release median in 1 of 157 timing and memory cells.

## Registration time (ns per route)

All peer configurations use the same candidate AOT executable for a given fixture. Each process registered 4,096 pregenerated routes with a shared handler. The result is the median of five fresh processes with rotating run order. Each process used one warmup and seven timed builds. The mixed table interleaves three parameter structures and a static route under the same first segment. The distinct-head table changes the first segment on every route. The opaque-key table uses nonnumeric service names of at least 25 characters. Shelf also registers HEAD for GET.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 78.1 | 538.0 (6.89×) | 435.3 (5.57×) | 1,476.0 (18.90×) |
| Two parameters | 89.9 | 945.2 (10.51×) | 805.9 (8.96×) | 3,352.1 (37.29×) |
| Four methods | 82.7 | 243.4 (2.94×) | 393.5 (4.76×) | 951.7 (11.51×) |
| Mixed structures | 444.9 | 932.0 (2.09×) | 789.5 (1.77×) | 2,050.5 (4.61×) |
| Distinct first segments | 108.2 | 688.4 (6.36×) | 606.1 (5.60×) | 2,209.9 (20.42×) |
| Deep static | 180.5 | 1,431.0 (7.93×) | 1,211.9 (6.71×) | 3,097.9 (17.16×) |
| Long opaque parameter-table keys | 169.7 | 1,164.6 (6.86×) | 934.2 (5.51×) | 4,028.8 (23.74×) |

The next measurement adds one differently shaped POST route to an existing two-parameter table. Building and verifying the table are outside that interval. Each process reports the median of 35 individual additions.

| Existing routes | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| 128 | 625.0 | 666.0 (1.07×) | 583.0 (0.93×) | 1,208.0 (1.93×) |
| 8,192 | 875.0 | 1,250.0 (1.43×) | 958.0 (1.09×) | 2,167.0 (2.48×) |

## Retained router heap (bytes per route)

Median of three Dart VM retained-size measurements after forced GC at 8,192 registrations. Each entry in the first table references one shared handler. Objects also retained by Relic’s global path interner are excluded from its exclusive size.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 56.1 | 232.1 (4.14×) | 264.0 (4.71×) | 632.0 (11.27×) |
| Two parameters | 56.1 | 1,128.1 (20.09×) | 1,224.0 (21.80×) | 1,240.0 (22.09×) |
| Four methods | 26.1 | 58.1 (2.23×) | 66.0 (2.53×) | 298.0 (11.43×) |
| Mixed structures | 406.0 | 754.1 (1.86×) | 826.0 (2.03×) | 954.0 (2.35×) |
| Distinct first segments | 56.1 | 680.0 (12.11×) | 744.0 (13.25×) | 1,144.0 (20.38×) |
| Deep static | 104.1 | 1,322.6 (12.71×) | 1,482.7 (14.25×) | 2,010.8 (19.32×) |
| Long opaque parameter-table keys | 72.2 | 1,128.1 (15.63×) | 1,240.1 (17.18×) | 1,304.1 (18.07×) |

Each entry below owns a distinct closure that returns its route ID. The probes verify the selected ID, including different methods on one path.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 136.1 | 312.1 (2.29×) | 344.0 (2.53×) | 712.0 (5.23×) |
| Two parameters | 136.1 | 1,208.1 (8.87×) | 1,304.0 (9.58×) | 1,320.0 (9.70×) |
| Four methods | 106.1 | 138.1 (1.30×) | 146.0 (1.38×) | 378.0 (3.56×) |

## Peak process RSS (MiB)

Each fresh AOT process constructs 32,768 routes, including incremental input generation. RSS includes the runtime, allocator, transient allocations and router. Each populated row is the median of three processes.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 19.45 | 59.53 (3.06×) | 46.19 (2.37×) | 67.91 (3.49×) |
| Two parameters | 23.42 | 83.42 (3.56×) | 83.25 (3.55×) | 85.91 (3.67×) |
| Four methods | 22.00 | 31.34 (1.42×) | 24.58 (1.12×) | 55.31 (2.51×) |
| Mixed structures | 41.66 | 78.25 (1.88×) | 70.28 (1.69×) | 77.66 (1.86×) |
| Distinct first segments | 23.83 | 78.02 (3.27×) | 59.91 (2.51×) | 84.05 (3.53×) |
| Deep static | 21.05 | 97.00 (4.61×) | 89.00 (4.23×) | 104.55 (4.97×) |
| Long opaque parameter-table keys | 24.41 | 88.70 (3.63×) | 77.84 (3.19×) | 87.86 (3.60×) |

The zero-route process control measured Roux 2.0.0 12.95 MiB, Roux research 13.05 MiB, Relic 13.05 MiB, Relic NoCache 13.02 MiB, shelf_router 13.00 MiB. It is excluded from the workload count.

## Pure lookup (ns per request)

The shuffled workload has 256 static and 256 two-parameter GET routes. The endpoint and both captured values are checked before timing. Relic’s default path interner holds 10,000 keys. Its 4,096-key working set fits and its 32,768-key working set exceeds capacity. Both use the same steady-state query schedule. The nested fixture checks the full capture and both groups. Relic uses a handler-side regex to produce equivalent results.

| Workload | Roux | Relic | Relic NoCache |
| --- | ---: | ---: | ---: |
| static | 39.5 | 146.7 (3.71×) | 400.4 (10.14×) |
| params-4k | 185.0 | 320.6 (1.73×) | 728.0 (3.94×) |
| params-32k | 192.0 | 4,578.6 (23.85×) | 734.8 (3.83×) |
| miss-4k | 128.1 | 210.2 (1.64×) | 604.1 (4.72×) |
| miss-32k | 132.7 | 4,277.2 (32.23×) | 615.9 (4.64×) |
| Nested regex | 162.3 | 397.3 (2.45×) | 648.7 (4.00×) |

## Shelf HTTP dispatch (ns per request)

Both sides dispatch the same pregenerated Shelf requests and construct equivalent responses. The timer includes the async call and inspection of the payload.

| Workload | Roux + Shelf | shelf_router |
| --- | ---: | ---: |
| static | 330.8 | 2,356.1 (7.12×) |
| params-4k | 447.8 | 3,329.6 (7.44×) |
| miss-4k | 408.2 | 877.3 (2.15×) |
| Nested regex | 457.4 | 2,701.0 (5.91×) |

## 10× target

| Comparator | At least 10× | At least 1× and below 10× | Below 1× | Total |
| --- | ---: | ---: | ---: | ---: |
| Relic | 7 | 25 | 0 | 32 |
| Relic NoCache | 5 | 26 | 1 | 32 |
| shelf_router | 12 | 18 | 0 | 30 |

Each cell represents one workload, metric and peer configuration. Cells receive equal weight. Time and memory are scored separately.

Measured losses were Relic NoCache on Late registration / 128 (0.93×).

## Regression gate against Roux 2.0.0

The release snapshot is aec52fa. Native AOT timings use five initial process pairs. Dart JIT and dart2js on Node 26.11.1 use three. Initially slower lookup suites received six more AOT pairs or two more JIT/JS pairs with reversed order. The table pools all original and follow-up samples. A positive paired delta means Roux took longer.

| Suite / case | Pairs | 2.0.0 | Research | Paired delta | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| lookup / regex32 | 11 | 165.0 | 171.7 | +6.2 | 10 |

The release gate covers 157 timing and memory cells, including the parameter-table RSS sweep from 4,096 to 131,072 routes. The number of pooled medians above the release was 1.

| Higher median | 2.0.0 | Research | Change |
| --- | ---: | ---: | ---: |
| lookup / regex32 | 165.0 | 171.7 | +4.06% |

The VM and compiled JavaScript each agreed with the release on 887,521 differential comparisons. The 53,568 new comparisons cover shared shapes, broad overlaps, registration of a different shape and removal at several positions of the varying literal.

After removing 8,191 of 8,192 static registrations, the surviving router retained 688 bytes. The release retained 197,296 bytes.

## Implementation size

Literal routes hold payloads directly. Parameter routes with a common shape share their capture names and keep one handler row per differing segment. When a new shape overlaps, the trie expands only that row.

The candidate contains 1,530 physical Dart source lines under lib/, compared with 814 in Roux 2.0.0 and 813 at the previous research checkpoint. The code-size reduction target remains open.

## Reproduction

The in-repository peer package reproduces the standard registration, peak RSS, shuffled lookup and HTTP dispatch workloads. It has its own dependency lockfile.

```sh
cd benchmark/peers && dart pub get --enforce-lockfile
dart compile exe registration.dart -o /tmp/roux-peer-register
dart compile exe lookup.dart -o /tmp/roux-peer-lookup
for r in roux relic relic-nocache shelf; do /tmp/roux-peer-register "$r" params 4096; done
for r in roux relic relic-nocache shelf; do /tmp/roux-peer-register "$r" methods 32768 rss; done
for r in roux relic relic-nocache roux-shelf shelf; do /tmp/roux-peer-lookup "$r"; done
```

The accompanying study bundle contains release and candidate sources, the peer lockfile, fixtures, drivers and per-process measurements. From its extracted directory, run the following commands in sequence.

```sh
(cd peers && dart pub get --enforce-lockfile)
export DART="$(command -v dart)"
python3 build.py base lookup registration register hot captures extra peers nested reversed cold remove tails prefixes peerbuild outlier
for b in lookup registration; do dart compile js -O2 --packages=base.json "benchmark/$b.dart" -o "base-$b.js"; done
sh formal.sh
python3 mem_matrix.py
python3 peer_report.py
```

The retained-size diagnostic uses a loopback VM-service port. The public lookup fixture is unchanged. The HTTP timings exclude socket transport.
