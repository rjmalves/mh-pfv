# Epic 03: Performance and Parallelization

## Goal

Introduce R-native parallelism using the future/parallel packages to process plants concurrently, cache expensive computations (Haversine distances), and establish benchmarking infrastructure to measure and prevent performance regressions.

## Scope

1. Add future/future.apply as dependencies
2. Replace `lapply` with `future_lapply` for per-plant processing in train and predict
3. Cache Haversine distance computations in `associa_nwp_usina()`
4. Add benchmarking infrastructure using bench or microbenchmark
5. Create performance baseline measurements

## Out of Scope

- Distributed computing (Spark, MPI)
- GPU acceleration
- Chunked/streaming data processing (data fits in memory)

## Success Criteria

- N-core speedup for N plants (near-linear scaling)
- Haversine cache eliminates redundant computation
- Benchmark suite captures performance metrics per commit
- No numerical differences from sequential processing

## Tickets

| ID       | Title                                                          | Effort | Dependencies |
| -------- | -------------------------------------------------------------- | ------ | ------------ |
| E03-T001 | Add future/future.apply dependency and parallel infrastructure | Small  | E02-T004     |
| E03-T002 | Parallelize train_main per-plant processing                    | Medium | E03-T001     |
| E03-T003 | Parallelize predict_main per-plant processing                  | Medium | E03-T002     |
| E03-T004 | Cache Haversine distance computations                          | Medium | E02-T004     |
| E03-T005 | Add benchmarking infrastructure and performance baseline       | Medium | E03-T003     |

## Estimated Duration

2 weeks with 2-3 developers.

## Dependencies on Other Epics

- **Epic 02**: Strategy pattern must be complete so parallelism operates on clean architecture
