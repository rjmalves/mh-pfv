# E03-T005 Add Benchmarking Infrastructure and Performance Baseline

## Context

### Background

After E03-T001 through E03-T004, the mhpfv package supports parallel plant processing and cached Haversine computations. However, there is no way to measure the actual speedup or detect performance regressions. This ticket creates a benchmarking infrastructure that measures execution time for the train and predict pipelines (sequential vs parallel), establishes baseline measurements, and provides a reproducible script for future comparisons.

### Relation to Epic

This is the final ticket in Epic 03. It validates and measures the performance improvements delivered by E03-T001 through E03-T004. Without it, the parallelization work has no measurable evidence of improvement and no regression detection.

### Current State

- No benchmarking infrastructure exists in the repository.
- No `benchmarks/` or `inst/benchmarks/` directory.
- The test data at `tests/testthat/data/` covers 2 plants (BAUFI1, BAUFI2) over July-September 2025.
- The `bench` package is a well-established R benchmarking library that provides `bench::mark()` with built-in memory profiling, garbage collection control, and tidy output.
- After E03-T002 and E03-T003, `train_main` and `predict_main` accept a `parallel` parameter.

## Specification

### Requirements

1. **Add `bench` to `Suggests`** in `DESCRIPTION` (not `Imports` -- benchmarks are optional).

2. **Create `inst/benchmarks/` directory** with the following scripts:
   - `benchmark-train.r` -- benchmarks `train_main()` sequential vs parallel.
   - `benchmark-predict.r` -- benchmarks `predict_main()` sequential vs parallel.
   - `benchmark-haversine.r` -- benchmarks `associa_nwp_usina()` with and without cache.
   - `run-all.r` -- master script that sources all benchmarks and produces a consolidated report.

3. **Each benchmark script must**:
   - Use `bench::mark()` for timing (with `check = FALSE` since parallel results may have different attributes but same values).
   - Accept a `data_dir` argument (default: the test data path) so it can be pointed at larger datasets.
   - Print results in a human-readable format (the tidy `bench_mark` tibble).
   - Save results to an RDS file in a configurable output directory for historical comparison.

4. **Create `R/benchmark-utils.r`** (internal, not exported) with helpers:
   - `run_benchmark(expr_list, names, iterations = 5)` -- wrapper around `bench::mark` with standard settings.
   - `compare_baselines(current, baseline)` -- compares two benchmark result sets and reports speedup/regression.
   - `save_benchmark_result(result, name, output_dir)` -- saves timestamped RDS.

5. **Establish baseline measurements** by running the benchmarks with the 2-plant test data and documenting the results in `inst/benchmarks/BASELINE.md`.

6. **Do NOT add benchmarks to CI** in this ticket. Benchmarks are run locally or on-demand. CI integration (if desired) belongs in Epic 05.

### Inputs/Props

- `benchmark-train.r`:
  - `data_dir`: character path to input data directory (default: package test data).
  - `n_iterations`: integer, number of benchmark iterations (default: 5).
  - `output_dir`: character path for saving results (default: `tempdir()`).

- `benchmark-predict.r`: same interface.

- `benchmark-haversine.r`:
  - `dt_usinas`: data.table with plant coordinates (generated if not provided).
  - `dt_irrad_prev`: data.table with NWP predictions (generated if not provided).
  - `n_iterations`: integer (default: 10).

### Outputs/Behavior

- Each benchmark script prints a `bench::mark` result table showing median time, memory allocation, and gc stats.
- Each script saves an RDS file named `<benchmark-name>_<ISO-timestamp>.rds` to the output directory.
- `run-all.r` produces a consolidated text report with all benchmarks and saves it as `benchmark-report_<timestamp>.txt`.
- `BASELINE.md` documents the initial baseline measurements (hardware, R version, dataset size, timings).

### Error Handling

- If `bench` is not installed, benchmark scripts should fail with a clear message: `stop("Package 'bench' is required. Install with: install.packages('bench')")`.
- If the test data directory does not exist, scripts should fail with a clear path error.
- If parallel benchmarks fail (e.g., due to insufficient memory for workers), catch the error and report it without crashing the entire benchmark suite.

## Acceptance Criteria

- [ ] Given `bench` is listed in `Suggests` in DESCRIPTION, when `devtools::check()` runs, then no errors about the bench dependency.
- [ ] Given `benchmark-train.r` is sourced with `data_dir` pointing to test data, when it completes, then it prints timing results for sequential and parallel `train_main`.
- [ ] Given `benchmark-predict.r` is sourced with `data_dir` pointing to test data, when it completes, then it prints timing results for sequential and parallel `predict_main`.
- [ ] Given `benchmark-haversine.r` is sourced, when it completes, then it prints timing results for cached vs uncached `associa_nwp_usina`.
- [ ] Given `run-all.r` is sourced, when it completes, then it produces a consolidated report and saves an RDS for each benchmark.
- [ ] Given a saved baseline RDS exists, when `compare_baselines()` is called with a new result, then it reports speedup or regression as a ratio.
- [ ] Given `BASELINE.md` exists in `inst/benchmarks/`, when inspected, then it documents hardware, R version, dataset dimensions, and timing results.
- [ ] Given `devtools::check()` is run, when it completes, then there are no new ERRORs or WARNINGs.

## Implementation Guide

### Suggested Approach

**Step 1: Add `bench` to `Suggests` in `DESCRIPTION`**

```
Suggests:
    bench (>= 1.1.0),
    testthat (>= 3.0.0)
```

**Step 2: Create `inst/benchmarks/` directory**

**Step 3: Create `benchmark-train.r`**

```r
# Benchmark: train_main sequential vs parallel
# Usage: Rscript inst/benchmarks/benchmark-train.r [data_dir]

suppressPackageStartupMessages({
    library(mhpfv)
    library(pfvIO)
    library(bench)
    library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
data_dir <- if (length(args) >= 1) args[1] else system.file("testdata", package = "mhpfv")

# If no testdata in package, try the testthat data directory
if (!dir.exists(data_dir) || data_dir == "") {
    data_dir <- file.path(system.file(package = "mhpfv"), "..", "..", "tests", "testthat", "data")
}
stopifnot(dir.exists(data_dir))

conn <- conectamock_pfv(data_dir)
config <- gen_config(mode = "train", janela = list("2025-07-01", "2025-09-30"))
config$input <- data_dir
config$artifact <- tempdir()
config <- parse_config(config, conn)

cat("Benchmarking train_main with", length(config$ids_usinas), "plants\n")
cat("Data directory:", data_dir, "\n\n")

results <- bench::mark(
    sequential = train_main(config, parallel = FALSE),
    parallel = train_main(config, parallel = TRUE),
    iterations = 5,
    check = FALSE
)

print(results)

# Save results
output_file <- file.path(tempdir(),
    paste0("benchmark-train_", format(Sys.time(), "%Y%m%dT%H%M%S"), ".rds"))
saveRDS(results, output_file)
cat("\nResults saved to:", output_file, "\n")
```

**Step 4: Create `benchmark-predict.r`** (same pattern as train)

**Step 5: Create `benchmark-haversine.r`**

```r
# Benchmark: associa_nwp_usina cached vs uncached

suppressPackageStartupMessages({
    library(mhpfv)
    library(bench)
    library(data.table)
})

# Generate synthetic data for benchmarking
n_plants <- 10
n_grid_points <- 50
dt_usinas <- data.table(
    id_usina = paste0("USI", seq_len(n_plants)),
    latitude = seq(-12, -25, length.out = n_plants),
    longitude = seq(-38, -50, length.out = n_plants),
    capacidade_instalada_MW = rep(28.0, n_plants),
    data_inicio_operacao_comercial = rep(as.POSIXct("2017-08-05", tz = "UTC"), n_plants)
)

# Generate grid of NWP coordinates
grid_lats <- seq(-12, -25, length.out = n_grid_points)
grid_lons <- seq(-38, -50, length.out = n_grid_points)
coord_grid <- CJ(latitude = grid_lats[1:10], longitude = grid_lons[1:5])

datas <- seq(as.POSIXct("2025-07-01", tz = "UTC"),
    as.POSIXct("2025-07-02", tz = "UTC"), by = "1 hour")

dt_irrad_prev <- CJ(
    id_modelo_nwp = "GFS",
    latitude = coord_grid$latitude,
    longitude = coord_grid$longitude,
    data_hora_rodada = datas[1],
    data_hora_previsao = datas
)[, valor := runif(.N, 0, 1000)]

cat("Benchmarking associa_nwp_usina\n")
cat("Plants:", n_plants, "| Grid points:", nrow(coord_grid), "\n\n")

# Uncached (clear cache before each iteration)
clear_haversine_cache()

results <- bench::mark(
    uncached = {
        clear_haversine_cache()
        associa_nwp_usina(dt_usinas, dt_irrad_prev)
    },
    cached = {
        associa_nwp_usina(dt_usinas, dt_irrad_prev)
    },
    iterations = 10,
    check = FALSE
)

print(results)
```

**Step 6: Create `run-all.r`** that sources all three benchmarks and combines output.

**Step 7: Create `BASELINE.md`** after running benchmarks locally. Document: hardware (CPU, RAM), R version, package versions, dataset dimensions, and median timings.

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/DESCRIPTION` -- add `bench` to Suggests
- `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-train.r` -- new file
- `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-predict.r` -- new file
- `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-haversine.r` -- new file
- `/home/rogerio/git/mh-pfv/inst/benchmarks/run-all.r` -- new file
- `/home/rogerio/git/mh-pfv/inst/benchmarks/BASELINE.md` -- new file (populated after running benchmarks)

### Patterns to Follow

- Use `bench::mark()` with `check = FALSE` when comparing sequential vs parallel results (parallel results may have different environment attributes).
- Use `suppressPackageStartupMessages()` for clean benchmark output.
- Use `system.file()` and `commandArgs()` for flexible data path resolution.
- Follow the test data setup patterns from `tests/testthat/helper-generators.r` when creating synthetic benchmark data.
- Document benchmark results in Markdown following the project's documentation conventions.

### Pitfalls to Avoid

- Do NOT run benchmarks as part of `testthat` tests -- they are slow and timing-sensitive. Keep them in `inst/benchmarks/` as standalone scripts.
- The 2-plant test dataset is very small. Benchmarks may show minimal or no speedup for parallel execution with only 2 plants (the overhead of serialization may exceed the benefit). This is expected. Document this in BASELINE.md and note that speedup scales with plant count.
- `bench::mark()` runs garbage collection between iterations by default. Do not disable this -- it ensures fair comparison.
- Benchmark scripts that use test data require the test data to exist. Use `stopifnot(dir.exists(data_dir))` for clear error messages.
- The Arrow ZSTD codec issue may affect benchmark scripts that read parquet data. Use `tryCatch` with informative messages if data loading fails.

## Testing Requirements

### Unit Tests

Not applicable in the traditional sense. Benchmark scripts are validated by running them, not by unit tests. However, add a minimal test:

File: `tests/testthat/test-benchmark-utils.r` (if `R/benchmark-utils.r` is created)

1. `save_benchmark_result()` creates an RDS file at the specified path.
2. `compare_baselines()` returns a data.frame with speedup ratios.
3. Both functions handle NULL/empty inputs gracefully.

Alternatively, if the benchmark helpers are kept entirely in `inst/benchmarks/` (not in `R/`), no unit tests are needed -- the benchmark scripts themselves serve as validation.

### Integration Tests

Run each benchmark script manually and verify:

1. It completes without error.
2. It prints results to console.
3. It saves an RDS file.
4. `run-all.r` produces a consolidated report.

This verification is documented in BASELINE.md rather than automated in CI.

## Dependencies

- **Blocked By**: E03-T003 (parallelize predict -- needed so benchmarks can compare sequential vs parallel), E03-T004 (cache haversine -- needed so haversine benchmarks can compare cached vs uncached)
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
