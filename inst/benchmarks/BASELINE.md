# mhpfv Performance Baseline

Baseline measurements established on 2026-02-17.

## Environment

| Property   | Value                                 |
| ---------- | ------------------------------------- |
| R version  | R 4.5.2 (2025-10-31)                  |
| Platform   | x86_64-redhat-linux-gnu               |
| OS         | Linux 6.18.9-200.fc43.x86_64 (Fedora) |
| CPU cores  | 20                                    |
| data.table | 1.17.8                                |
| bench      | 1.1.4                                 |
| future     | 1.69.0                                |

## Haversine / NWP Association (`associa_nwp_usina`)

This benchmark measures the cost of finding the nearest NWP grid point for
each plant using the Haversine distance formula, comparing uncached (full
recomputation) vs cached lookups.

### 20 plants, 7 days (6,720 irradiance rows)

| Mode     | Median  | Min     | Memory  | Iterations |
| -------- | ------- | ------- | ------- | ---------- |
| uncached | 30.5 ms | 28.4 ms | 7.14 MB | 16         |
| cached   | 19.1 ms | 17.9 ms | 4.82 MB | 25         |

**Cache speedup: 1.6x (median)**

### 50 plants, 14 days (33,600 irradiance rows)

| Mode     | Median  | Min     | Memory  | Iterations |
| -------- | ------- | ------- | ------- | ---------- |
| uncached | 84.2 ms | 76.2 ms | 25.7 MB | 6          |
| cached   | 52.0 ms | 47.8 ms | 20.5 MB | 10         |

**Cache speedup: 1.6x (median)**

### Interpretation

The cache avoids recomputing the O(N\*M) Haversine distance matrix (N plants,
M grid points) on repeated calls with the same coordinate sets. The 1.6x
speedup at this scale reflects that the filtering and `rbindlist` assembly
dominate the small synthetic grid. In production, where grids are denser
(e.g., ECMWF 0.25-degree with thousands of points), the Haversine
computation cost grows quadratically and the cache benefit is substantially
larger.

## Train Pipeline (`train_main`)

**Status: not measured** -- the test dataset uses a parquet file that requires
the zstd codec. If your arrow installation supports zstd, run:

```bash
Rscript inst/benchmarks/benchmark-train.r
```

Expected columns in the output: sequential vs parallel median time, memory
allocation, and iteration count.

With only 2 plants in the test dataset, parallel overhead is likely to
dominate. Meaningful speedup requires 10+ plants.

## Predict Pipeline (`predict_main`)

**Status: not measured** -- same parquet/zstd dependency as the train
benchmark. Run when available:

```bash
Rscript inst/benchmarks/benchmark-predict.r
```

## How to Reproduce

From the package root:

```bash
# Single benchmark
Rscript -e 'pkgload::load_all("."); source("inst/benchmarks/benchmark-haversine.r"); benchmark_haversine()'

# All benchmarks (haversine always runs; train/predict require arrow+zstd)
Rscript inst/benchmarks/run-all.r

# Custom data directory for train/predict
Rscript inst/benchmarks/run-all.r /path/to/data
```

Results are saved as RDS and plain text report in a timestamped temporary
directory printed at the end of each run.
