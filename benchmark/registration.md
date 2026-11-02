# Roux against Relic and shelf_router

Measured 2026-11-03 on macOS 27.2 arm64 with Dart 3.13.7, Relic Core 1.2.0 and shelf_router 1.1.5 with Shelf 1.4.3. Every multiplier divides the peer’s time or memory by Roux’s. A value of 2× means Roux used half as much. A value below 1× means the peer won.

Of 94 peer comparisons, 24 reached 10×, 70 reached parity but fell short of 10×, and 0 fell below parity. Roux exceeded the release median in 0 of 157 timing and memory cells. The separate high-resolution Node wildcard registration probe measured 833.5 ns/route versus 797.1 in 2.0.0 (+4.57%).

## Registration time (ns per route)

All peer configurations use the same candidate AOT executable for a given fixture. Each process registered 4,096 pregenerated routes with a shared handler. The result is the median of five fresh processes with rotating run order. Each process used one warmup and seven timed builds. The mixed table interleaves three parameter structures and a static route under the same first segment. The distinct-head table changes the first segment on every route. The opaque-key table uses nonnumeric service names of at least 25 characters. Shelf also registers HEAD for GET.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 77.2 | 527.9 (6.84×) | 435.3 (5.64×) | 1,458.1 (18.89×) |
| Two parameters | 87.9 | 907.5 (10.32×) | 765.2 (8.71×) | 3,202.6 (36.43×) |
| Four methods | 80.4 | 231.4 (2.88×) | 371.1 (4.62×) | 940.0 (11.69×) |
| Mixed structures | 359.2 | 911.8 (2.54×) | 780.4 (2.17×) | 1,973.8 (5.49×) |
| Distinct first segments | 104.4 | 674.1 (6.46×) | 599.5 (5.74×) | 2,125.3 (20.36×) |
| Deep static | 188.9 | 1,363.1 (7.22×) | 1,174.1 (6.22×) | 2,917.6 (15.45×) |
| Long opaque parameter-table keys | 161.9 | 1,137.9 (7.03×) | 907.6 (5.61×) | 3,870.3 (23.91×) |

Late registration adds one differently shaped POST route to an existing two-parameter table. The single-add probe reports medians of 35 additions in each of eleven fresh processes. The seven-process batch cross-check times one addition on each of 48 independent routers at size 128, or eight at size 8,192. It uses a distinct path per router. Table construction and verification are outside both timers. The single-add rows count toward the score. All timings are ns per added route.

| Probe / existing routes | Checkpoint e47c912 | Roux | Relic | Relic NoCache | shelf_router | Roux wins vs NoCache |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Single / 128 | 583.0 | 375.0 | 625.0 (1.67×) | 542.0 (1.45×) | 1,167.0 (3.11×) | 10/11 |
| Single / 8,192 | 709.0 | 459.0 | 1,000.0 (2.18×) | 709.0 (1.54×) | 1,750.0 (3.81×) | 11/11 |
| Batch / 128 | 579.0 | 405.4 | 702.3 (1.73×) | 616.3 (1.52×) | 1,272.6 (3.14×) | 7/7 |
| Batch / 8,192 | 588.5 | 401.0 | 1,505.3 (3.75×) | 1,171.9 (2.92×) | 3,046.9 (7.60×) | 7/7 |

## Retained router heap (bytes per route)

Median of three Dart VM retained-size measurements after forced GC at 8,192 registrations. Each entry in the first table references one shared handler. Objects also retained by Relic’s global path interner are excluded from its exclusive size.

| Table | Roux | Relic | Relic NoCache | shelf_router |
| --- | ---: | ---: | ---: | ---: |
| Static | 56.0 | 232.1 (4.14×) | 264.0 (4.71×) | 632.0 (11.28×) |
| Two parameters | 56.1 | 1,128.1 (20.10×) | 1,224.0 (21.81×) | 1,240.0 (22.09×) |
| Four methods | 26.1 | 58.1 (2.23×) | 66.0 (2.53×) | 298.0 (11.44×) |
| Mixed structures | 406.0 | 754.1 (1.86×) | 826.0 (2.03×) | 954.0 (2.35×) |
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
| Static | 19.23 | 59.62 (3.10×) | 46.25 (2.40×) | 68.09 (3.54×) |
| Two parameters | 23.47 | 83.50 (3.56×) | 82.80 (3.53×) | 86.61 (3.69×) |
| Four methods | 21.98 | 31.45 (1.43×) | 24.61 (1.12×) | 54.88 (2.50×) |
| Mixed structures | 42.73 | 78.75 (1.84×) | 69.89 (1.64×) | 77.69 (1.82×) |
| Distinct first segments | 23.83 | 78.05 (3.28×) | 59.91 (2.51×) | 84.05 (3.53×) |
| Deep static | 21.09 | 96.73 (4.59×) | 89.06 (4.22×) | 104.58 (4.96×) |
| Long opaque parameter-table keys | 24.41 | 88.77 (3.64×) | 77.86 (3.19×) | 87.89 (3.60×) |

The zero-route process control measured Roux 2.0.0 12.92 MiB, Roux research 13.05 MiB, Relic 13.05 MiB, Relic NoCache 13.06 MiB, shelf_router 13.09 MiB. It is excluded from the workload count.

## Pure lookup (ns per request)

The shuffled workload has 256 static and 256 two-parameter GET routes. The endpoint and both captured values are checked before timing. Relic’s default path interner holds 10,000 keys. Its 4,096-key working set fits and its 32,768-key working set exceeds capacity. Both use the same steady-state query schedule. The nested fixture checks the full capture and both groups. Relic uses a handler-side regex to produce equivalent results.

| Workload | Roux | Relic | Relic NoCache |
| --- | ---: | ---: | ---: |
| static | 38.0 | 145.3 (3.82×) | 397.5 (10.46×) |
| params-4k | 196.6 | 315.4 (1.60×) | 721.2 (3.67×) |
| params-32k | 199.6 | 4,368.1 (21.88×) | 728.0 (3.65×) |
| miss-4k | 138.1 | 206.8 (1.50×) | 599.3 (4.34×) |
| miss-32k | 141.5 | 4,199.5 (29.68×) | 607.8 (4.30×) |
| Nested regex | 166.6 | 384.3 (2.31×) | 624.7 (3.75×) |

## Shelf HTTP dispatch (ns per request)

Both sides dispatch the same pregenerated Shelf requests and construct equivalent responses. The timer includes the async call and inspection of the payload.

| Workload | Roux + Shelf | shelf_router |
| --- | ---: | ---: |
| static | 317.0 | 2,318.4 (7.31×) |
| params-4k | 463.7 | 3,273.0 (7.06×) |
| miss-4k | 404.3 | 864.5 (2.14×) |
| Nested regex | 419.1 | 2,509.7 (5.99×) |

## 10× target

| Comparator | At least 10× | At least 1× and below 10× | Below 1× | Total |
| --- | ---: | ---: | ---: | ---: |
| Relic | 7 | 25 | 0 | 32 |
| Relic NoCache | 5 | 27 | 0 | 32 |
| shelf_router | 12 | 18 | 0 | 30 |

Each cell represents one workload, metric and peer configuration. Cells receive equal weight. Time and memory are scored separately.

The smallest peer-to-Roux ratio was 1.12× against Relic NoCache on Peak RSS / Four methods.

At the four-method peak RSS of 24.61 MiB for Relic NoCache, a 10× result would require Roux to stay within 2.46 MiB. This Roux AOT executable measured 13.05 MiB with zero registrations.

## Regression gate against Roux 2.0.0

The release snapshot is aec52fa. Native AOT timings use five initial process pairs. Dart JIT and dart2js on Node 26.11.1 use three. The public AOT lookup and Node registration suites always receive six and two additional pairs, respectively. Other initially slower lookup suites receive the same runtime-specific follow-up. All cases in repeated suites use pooled medians. The table shows the two preselected checks and any case with a slower initial or pooled median. A positive paired delta means Roux took longer.

| Suite / case | Pairs | 2.0.0 | Research | Paired delta | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| lookup / regex32 | 11 | 164.1 | 157.6 | -6.6 | 0 |
| js-registration / wildcard | 5 | 732.4 | 732.4 | +0.0 | 0 |

The release gate covers 157 timing and memory cells, including the parameter-table RSS sweep from 4,096 to 131,072 routes. All pooled medians were at or below the release.

All 70 unit tests pass on the VM and Node.js. The VM and compiled JavaScript each agreed with the release on 887,521 differential comparisons. The 53,568 new comparisons cover shared shapes, broad overlaps, registration of a different shape and removal at several positions of the varying literal.

After removing 8,191 of 8,192 static registrations, the surviving router retained 528 bytes. The release retained 197,296 bytes.

The Node clock resolves to 244.1 ns per route in the 4,096-route registration probe. Two larger runs of the same wildcard registration fixture give finer time resolution. Each row is a median of five processes. They are reported separately from the 157-cell release gate.

| Node wildcard registrations | 2.0.0 | Checkpoint | Roux | Change vs 2.0.0 |
| --- | ---: | ---: | ---: | ---: |
| 16,384 | 915.5 | 671.4 | 732.4 | -20.00% |
| 32,768 | 946.0 | 671.4 | 671.4 | -29.03% |

A separate seven-process run at 4,096 routes uses Node’s performance.now through dart2js’s window.performance clock adapter. The router and Dart benchmark sources are identical. This diagnostic does not replace the original Node readings.

| High-resolution Node registration | 2.0.0 | Checkpoint | Roux | Change vs 2.0.0 |
| --- | ---: | ---: | ---: | ---: |
| static | 824.7 | 129.4 | 129.2 | -84.33% |
| params | 1,655.8 | 157.5 | 159.9 | -90.34% |
| wildcard | 797.1 | 781.0 | 833.5 | +4.57% |
| nested | 5,016.6 | 4,045.2 | 4,092.0 | -18.43% |
| indexed | 2,163.1 | 1,872.8 | 1,903.1 | -12.02% |
| methods | 714.8 | 116.0 | 119.1 | -83.34% |
| optional | 2,157.5 | 1,815.2 | 1,800.3 | -16.56% |

## Checkpoint comparison

Same-machine measurements against the pre-change commit e47c912. Timings are in ns per operation. Retained heap is in bytes per route and peak process RSS is in MiB. The complete before/after samples for every measured checkpoint cell are in the bundle.

| Workload | Checkpoint | Roux | Change |
| --- | ---: | ---: | ---: |
| peer-reg-static / add | 73.1 | 77.2 | +5.61% |
| peer-reg-params / add | 89.5 | 87.9 | -1.79% |
| peer-reg-methods / add | 78.5 | 80.4 | +2.42% |
| peer-rss-params / peak | 23.4 | 23.5 | +0.20% |
| peer-reg-mixed / add | 445.3 | 359.2 | -19.34% |
| peer-reg-heads / add | 103.5 | 104.4 | +0.87% |
| peer-reg-deep / add | 176.6 | 188.9 | +6.96% |
| peer-reg-opaque / add | 161.0 | 161.9 | +0.56% |
| checkpoint-public / regex32 | 170.7 | 157.6 | -7.67% |
| checkpoint-public / hot /nested/Report-42 | 165.5 | 181.5 | +9.67% |
| peer / params | 56.1 | 56.1 | -0.02% |
| peer / mixed | 406.0 | 406.0 | -0.00% |

58 of these 95 checkpoint medians increased. The following list includes every increase of at least 5%. Smaller changes and the complete raw samples are in results/summary.json and results/memory.jsonl. The 5% cutoff is used only to shorten this list. The release gate above counts every increase.

| Candidate at least 5% above checkpoint | Checkpoint | Roux | Change |
| --- | ---: | ---: | ---: |
| peer-reg-static / add | 73.1 | 77.2 | +5.61% |
| peer-reg-deep / add | 176.6 | 188.9 | +6.96% |
| checkpoint-public / params | 130.9 | 137.8 | +5.27% |
| checkpoint-public / regex | 108.1 | 118.6 | +9.71% |
| checkpoint-public / hot /nested/Report-42 | 165.5 | 181.5 | +9.67% |
| checkpoint-hot / param | 79.0 | 83.4 | +5.57% |
| checkpoint-hot / regex | 93.7 | 99.5 | +6.19% |
| checkpoint-hot / embedded | 130.8 | 143.7 | +9.86% |
| checkpoint-hot / two-regex | 216.4 | 234.6 | +8.41% |
| checkpoint-extra / root | 16.9 | 19.5 | +15.38% |
| checkpoint-extra / empty | 16.1 | 18.5 | +14.91% |
| checkpoint-cold / params | 184.1 | 200.1 | +8.69% |
| checkpoint-cold / nested | 296.6 | 314.2 | +5.93% |
| checkpoint-cold / fallback | 414.2 | 436.4 | +5.36% |
| checkpoint-cold / duplicate-all | 599.7 | 647.0 | +7.89% |
| checkpoint-remove / ascending | 63.3 | 87.6 | +38.39% |
| checkpoint-remove / descending | 68.8 | 96.2 | +39.83% |
| checkpoint-remove / alternating | 68.0 | 92.3 | +35.74% |
| checkpoint-remove / random | 79.2 | 103.4 | +30.56% |
| checkpoint-remove / churn | 134.7 | 172.7 | +28.21% |
| checkpoint-tails / tail-1 | 71.3 | 79.0 | +10.80% |
| checkpoint-peer-lookups / params-4k | 184.6 | 195.8 | +6.07% |
| checkpoint-peer-lookups / miss-4k | 126.6 | 138.3 | +9.24% |
| checkpoint-peer-lookups / miss-32k | 130.3 | 140.3 | +7.67% |
| checkpoint-dispatch / params-4k | 442.1 | 465.1 | +5.20% |
| checkpoint-dispatch / miss-4k | 385.3 | 404.9 | +5.09% |
| checkpoint-reg-wildcard / wildcard | 357.7 | 380.5 | +6.37% |

## Implementation size

Literal routes hold payloads directly. Parameter routes with a common shape share their capture names and keep one handler row per differing segment. When a new shape overlaps, the trie expands only that row.

The candidate contains 1,527 physical Dart source lines under lib/. The checkpoint has 1,530 (-3 lines in the candidate) and the release has 814. The shared branch uses the existing single-child store and allocates a sibling map only when it needs a second concrete child. Registration and removal reuse the literal prefix they already decoded. Wildcards and constraints share the same capture-position plan. The regex index hashes only the variable portion of a common prefix, retaining registration order for collisions and checking the complete regex before accepting a result.

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

The accompanying study bundle contains release, checkpoint and candidate sources, the peer lockfile, fixtures, drivers and per-process measurements. From its extracted directory, run the following commands in sequence.

```sh
(cd peers && dart pub get --enforce-lockfile)
export DART="$(command -v dart)"
mv results recorded-results
sh formal.sh
python3 mem_matrix.py
python3 peer_report.py
```

The retained-size diagnostic uses a loopback VM-service port. The public lookup fixture is unchanged. The HTTP timings exclude socket transport.
