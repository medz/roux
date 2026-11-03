# Roux against Relic and shelf_router

Measured 2026-11-03 on macOS 27.2 arm64 with Dart 3.13.7, Relic Core 1.2.0 and shelf_router 1.1.5 with Shelf 1.4.3. Every multiplier divides the peer’s time or memory by Roux’s. A value of 2× means Roux used half as much. A value below 1× means the peer won.

Of 94 peer comparisons, 24 reached 10×, 70 reached parity but fell short of 10×, and 0 fell below parity. Roux exceeded the release median in 0 of 157 timing and memory cells. The separate high-resolution Node wildcard registration probe measured 678.5 ns/route versus 776.6 in 2.0.0 (-12.63%).

## Registration time (ns per route)

All peer configurations use the same candidate AOT executable for a given fixture. Each process registered 4,096 pregenerated routes with a shared handler. The result is the median of five fresh processes with rotating run order. Each process used one warmup and seven timed builds. The mixed table interleaves three parameter structures and a static route under the same first segment. The distinct-head table changes the first segment on every route. The opaque-key table uses nonnumeric service names of at least 25 characters. Shelf also registers HEAD for GET.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 74.1 | 525.3 (7.09×) | 436.0 (5.88×) | 1,456.9 (19.66×) |
| Two parameters | 89.9 | 912.9 (10.15×) | 791.8 (8.81×) | 3,239.2 (36.03×) |
| Four methods | 78.6 | 239.7 (3.05×) | 377.3 (4.80×) | 938.9 (11.95×) |
| Mixed structures | 350.7 | 914.7 (2.61×) | 786.9 (2.24×) | 1,989.3 (5.67×) |
| Distinct first segments | 104.3 | 682.5 (6.54×) | 599.2 (5.74×) | 2,156.4 (20.67×) |
| Deep static | 183.6 | 1,383.5 (7.54×) | 1,184.1 (6.45×) | 2,933.9 (15.98×) |
| Long opaque parameter-table keys | 161.9 | 1,144.1 (7.07×) | 921.5 (5.69×) | 3,872.9 (23.92×) |

Late registration adds one differently shaped POST route to an existing two-parameter table. The single-add probe reports medians of 35 additions in each of eleven fresh processes. The seven-process batch cross-check times one addition on each of 48 independent routers at size 128, or eight at size 8,192. It uses a distinct path per router. Table construction and verification are outside both timers. The single-add rows count toward the score. All timings are ns per added route.

| Probe / existing routes | Checkpoint e47c912 | Roux | Relic | Relic NoCache | shelf_router | Roux wins vs NoCache |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Single / 128 | 625.0 | 375.0 | 666.0 (1.78×) | 583.0 (1.55×) | 1,167.0 (3.11×) | 10/11 |
| Single / 8,192 | 750.0 | 458.0 | 1,000.0 (2.18×) | 708.0 (1.55×) | 1,750.0 (3.82×) | 11/11 |
| Batch / 128 | 565.1 | 364.6 | 704.9 (1.93×) | 619.8 (1.70×) | 1,279.5 (3.51×) | 7/7 |
| Batch / 8,192 | 588.6 | 369.8 | 1,500.0 (4.06×) | 1,177.1 (3.18×) | 3,187.5 (8.62×) | 7/7 |

## Retained router heap (bytes per route)

Median of three Dart VM retained-size measurements after forced GC at 8,192 registrations. Each entry in the first table references one shared handler. Objects also retained by Relic’s global path interner are excluded from its exclusive size.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 56.0 | 232.1 (4.14×) | 264.0 (4.71×) | 632.0 (11.28×) |
| Two parameters | 56.1 | 1,128.1 (20.10×) | 1,224.0 (21.81×) | 1,240.0 (22.09×) |
| Four methods | 26.1 | 58.1 (2.23×) | 66.0 (2.53×) | 298.0 (11.44×) |
| Mixed structures | 378.0 | 754.1 (1.99×) | 826.0 (2.19×) | 954.0 (2.52×) |
| Distinct first segments | 56.1 | 680.0 (12.12×) | 744.0 (13.26×) | 1,144.0 (20.38×) |
| Deep static | 104.0 | 1,322.6 (12.71×) | 1,482.7 (14.25×) | 2,010.8 (19.33×) |
| Long opaque parameter-table keys | 72.2 | 1,128.1 (15.63×) | 1,240.1 (17.18×) | 1,304.1 (18.07×) |

Each entry below owns a distinct closure that returns its route ID. The probes verify the selected ID, including different methods on one path.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 136.0 | 312.1 (2.29×) | 344.0 (2.53×) | 712.0 (5.23×) |
| Two parameters | 136.1 | 1,208.1 (8.87×) | 1,304.0 (9.58×) | 1,320.0 (9.70×) |
| Four methods | 106.1 | 138.1 (1.30×) | 146.0 (1.38×) | 378.0 (3.56×) |

## Peak process RSS (MiB)

Each fresh AOT process constructs 32,768 routes, including incremental input generation. RSS includes the runtime, allocator, transient allocations and router. Each populated row is the median of three processes.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 19.23 | 59.52 (3.09×) | 46.23 (2.40×) | 68.03 (3.54×) |
| Two parameters | 23.42 | 83.52 (3.57×) | 82.75 (3.53×) | 85.94 (3.67×) |
| Four methods | 21.97 | 31.44 (1.43×) | 24.58 (1.12×) | 55.45 (2.52×) |
| Mixed structures | 40.20 | 78.70 (1.96×) | 69.94 (1.74×) | 77.69 (1.93×) |
| Distinct first segments | 23.78 | 78.02 (3.28×) | 59.91 (2.52×) | 84.03 (3.53×) |
| Deep static | 21.05 | 96.72 (4.60×) | 88.98 (4.23×) | 104.55 (4.97×) |
| Long opaque parameter-table keys | 24.39 | 88.75 (3.64×) | 77.84 (3.19×) | 87.84 (3.60×) |

The zero-route process control measured Roux 2.0.0 12.94 MiB, Roux research 13.02 MiB, Relic 13.02 MiB, Relic NoCache 13.05 MiB, shelf_router 13.08 MiB. It is excluded from the workload count.

## Pure lookup (ns per request)

The shuffled workload has 256 static and 256 two-parameter GET routes. The endpoint and both captured values are checked before timing. Relic’s default path interner holds 10,000 keys. Its 4,096-key working set fits and its 32,768-key working set exceeds capacity. Both use the same steady-state query schedule. The nested fixture checks the full capture and both groups. Relic uses a handler-side regex to produce equivalent results.

| Workload | Roux | Relic | Relic NoCache |
| --- | ---: | ---: | ---: |
| static | 38.0 | 145.7 (3.83×) | 398.7 (10.49×) |
| params-4k | 196.6 | 319.9 (1.63×) | 721.0 (3.67×) |
| params-32k | 199.9 | 4,414.1 (22.08×) | 726.8 (3.64×) |
| miss-4k | 138.1 | 207.1 (1.50×) | 599.2 (4.34×) |
| miss-32k | 141.0 | 4,202.6 (29.81×) | 606.3 (4.30×) |
| Nested regex | 170.8 | 402.8 (2.36×) | 627.7 (3.68×) |

## Shelf HTTP dispatch (ns per request)

Both sides dispatch the same pregenerated Shelf requests and construct equivalent responses. The timer includes the async call and inspection of the payload.

| Workload | Roux + Shelf | shelf_router |
| --- | ---: | ---: |
| static | 317.1 | 2,295.4 (7.24×) |
| params-4k | 465.3 | 3,250.8 (6.99×) |
| miss-4k | 404.3 | 865.0 (2.14×) |
| Nested regex | 426.1 | 2,531.6 (5.94×) |

## 10× target

| Comparator | At least 10× | At least 1× and below 10× | Below 1× | Total |
| --- | ---: | ---: | ---: | ---: |
| Relic | 7 | 25 | 0 | 32 |
| Relic NoCache | 5 | 27 | 0 | 32 |
| shelf_router | 12 | 18 | 0 | 30 |

Each cell represents one workload, metric and peer configuration. Cells receive equal weight. Time and memory are scored separately.

The smallest peer-to-Roux ratio was 1.12× against Relic NoCache on Peak RSS / Four methods.

At the four-method peak RSS of 24.58 MiB for Relic NoCache, a 10× result would require Roux to stay within 2.46 MiB. This Roux AOT executable measured 13.02 MiB with zero registrations.

## Regression gate against Roux 2.0.0

The release snapshot is aec52fa. Native AOT timings use five initial process pairs. Dart JIT and dart2js on Node 26.11.1 use three. The public AOT lookup and Node registration suites always receive six and two additional pairs, respectively. Other initially slower lookup suites receive the same runtime-specific follow-up. All cases in repeated suites use pooled medians. The table shows the two preselected checks and any case with a slower initial or pooled median. A positive paired delta means Roux took longer.

| Suite / case | Pairs | 2.0.0 | Research | Paired delta | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| lookup / regex32 | 11 | 164.6 | 156.6 | -7.9 | 0 |
| js-registration / wildcard | 5 | 732.4 | 732.4 | +0.0 | 0 |

The release gate covers 157 timing and memory cells, including the parameter-table RSS sweep from 4,096 to 131,072 routes. All pooled medians were at or below the release.

All 70 unit tests pass on the VM and Node.js. The VM and compiled JavaScript each agreed with the release on 887,521 differential comparisons. The 53,568 new comparisons cover shared shapes, broad overlaps, registration of a different shape and removal at several positions of the varying literal.

After removing 8,191 of 8,192 static registrations, the surviving router retained 528 bytes. The release retained 197,296 bytes.

The Node clock resolves to 244.1 ns per route in the 4,096-route registration probe. Two larger runs of the same wildcard registration fixture give finer time resolution. Each row is a median of five processes. They are reported separately from the 157-cell release gate.

| Node wildcard registrations | 2.0.0 | Checkpoint | Roux | Change vs 2.0.0 |
| --- | ---: | ---: | ---: | ---: |
| 16,384 | 915.5 | 732.4 | 671.4 | -26.66% |
| 32,768 | 976.6 | 640.9 | 640.9 | -34.37% |

A separate seven-process run at 4,096 routes uses Node’s performance.now through dart2js’s window.performance clock adapter. The router and Dart benchmark sources are identical. This diagnostic does not replace the original Node readings.

| High-resolution Node registration | 2.0.0 | Checkpoint | Roux | Change vs 2.0.0 |
| --- | ---: | ---: | ---: | ---: |
| static | 817.4 | 129.2 | 124.5 | -84.77% |
| params | 1,608.2 | 159.2 | 157.0 | -90.24% |
| wildcard | 776.6 | 819.6 | 678.5 | -12.63% |
| nested | 5,010.7 | 4,084.2 | 3,817.9 | -23.81% |
| indexed | 2,173.6 | 1,910.6 | 1,706.1 | -21.51% |
| methods | 710.0 | 115.7 | 118.9 | -83.25% |
| optional | 2,144.8 | 1,776.4 | 1,723.9 | -19.62% |

## Checkpoint comparison

Same-machine measurements against the pre-change commit e47c912. Timings are in ns per operation. Retained heap is in bytes per route and peak process RSS is in MiB. The complete before/after samples for every measured checkpoint cell are in the bundle.

| Workload | Checkpoint | Roux | Change |
| --- | ---: | ---: | ---: |
| peer-reg-static / add | 75.9 | 74.1 | -2.37% |
| peer-reg-params / add | 90.2 | 89.9 | -0.33% |
| peer-reg-methods / add | 77.7 | 78.6 | +1.16% |
| peer-rss-params / peak | 23.5 | 23.4 | -0.33% |
| peer-reg-mixed / add | 446.1 | 350.7 | -21.39% |
| peer-reg-heads / add | 108.0 | 104.3 | -3.43% |
| peer-reg-deep / add | 178.1 | 183.6 | +3.09% |
| peer-reg-opaque / add | 160.8 | 161.9 | +0.68% |
| checkpoint-public / regex32 | 172.9 | 156.9 | -9.25% |
| checkpoint-public / hot /nested/Report-42 | 167.6 | 180.1 | +7.46% |
| peer / params | 56.1 | 56.1 | -0.02% |
| peer / mixed | 406.0 | 378.0 | -6.90% |

45 of these 95 checkpoint medians increased. The following list includes every increase of at least 5%. Smaller changes and the complete raw samples are in results/summary.json and results/memory.jsonl. The 5% cutoff is used only to shorten this list. The release gate above counts every increase.

| Candidate at least 5% above checkpoint | Checkpoint | Roux | Change |
| --- | ---: | ---: | ---: |
| checkpoint-public / params | 132.6 | 140.0 | +5.58% |
| checkpoint-public / hot /nested/Report-42 | 167.6 | 180.1 | +7.46% |
| checkpoint-hot / param | 79.8 | 87.5 | +9.65% |
| checkpoint-hot / regex | 93.8 | 99.2 | +5.76% |
| checkpoint-hot / embedded | 131.9 | 140.9 | +6.82% |
| checkpoint-hot / two-regex | 217.5 | 232.6 | +6.94% |
| checkpoint-hot / rotating | 81.0 | 85.9 | +6.05% |
| checkpoint-extra / root | 16.8 | 21.4 | +27.38% |
| checkpoint-extra / empty | 16.4 | 20.3 | +23.78% |
| checkpoint-cold / params | 185.5 | 199.1 | +7.33% |
| checkpoint-cold / nested | 290.0 | 316.9 | +9.28% |
| checkpoint-cold / duplicate-all | 601.6 | 641.4 | +6.62% |
| checkpoint-tails / tail-1 | 73.0 | 81.4 | +11.51% |
| checkpoint-peer-lookups / params-4k | 184.8 | 196.9 | +6.55% |
| checkpoint-peer-lookups / miss-4k | 128.1 | 138.8 | +8.35% |
| checkpoint-peer-lookups / miss-32k | 129.6 | 140.5 | +8.41% |

## Implementation size

Literal routes hold payloads directly. Parameter routes with a common shape share their capture names and keep one handler row per differing segment. When a new shape overlaps, the trie expands only that row.

The candidate contains 1,529 physical Dart source lines under lib/. The checkpoint has 1,530 (-1 lines in the candidate) and the release has 814. The shared branch uses the existing single-child store and allocates a sibling map only when it needs a second concrete child. Registration and removal reuse the literal prefix they already decoded. A route with one capture stores its key and position directly. Routes with multiple captures store the gaps between keys. Row maps compact when deletions bring them down to a quarter of their earlier size. The regex index hashes only the variable portion of a common prefix, retaining registration order for collisions and checking the complete regex before accepting a result.

## Reproduction

The in-repository peer package reproduces the standard registration, peak RSS, shuffled lookup and HTTP dispatch workloads. It has its own dependency lockfile.

```sh
cd benchmark/peers && dart pub get --enforce-lockfile
dart compile exe registration.dart -o /tmp/roux-peer-register
dart compile exe lookup.dart -o /tmp/roux-peer-lookup
dart compile exe late_registration.dart -o /tmp/roux-late-register
for r in roux relic relic-nocache shelf; do /tmp/roux-late-register "$r"; done
for r in roux relic relic-nocache shelf; do /tmp/roux-peer-register "$r" params 4096; done
for r in roux relic relic-nocache shelf; do /tmp/roux-peer-register "$r" methods 32768 rss; done
for r in roux relic relic-nocache roux-shelf shelf; do /tmp/roux-peer-lookup "$r"; done
```

The archive contains the release, checkpoint and candidate sources, the peer lockfile, fixtures, drivers and per-process measurements. [Download the study bundle (ZIP)](./roux-competitors-2026-11-03.zip).

Extract the archive and run the following commands from its directory.

```sh
(cd peers && dart pub get --enforce-lockfile)
export DART="$(command -v dart)"
mv results recorded-results
sh formal.sh
python3 mem_matrix.py
python3 peer_report.py
```

The retained-size diagnostic uses a loopback VM-service port. The public lookup fixture is unchanged. The HTTP timings exclude socket transport.
