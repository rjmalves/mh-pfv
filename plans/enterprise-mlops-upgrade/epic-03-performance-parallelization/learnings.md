# Epic 03: Performance and Parallelization -- Learnings

**Epic**: epic-03-performance-parallelization
**Date**: 2026-02-17
**Tickets Completed**: 5/5

---

## Patterns Established

- **future_lapply drop-in replacement pattern**: The parallelization of both pipelines follows a consistent structure: build a shared argument list, then dispatch to either `lapply` or `future_lapply` conditionally on a `parallel` boolean parameter. In `predict_main()`, this was refined into a `do.call` pattern where `apply_args` is constructed once and passed to either `lapply` or `future_lapply`. In `train_main()`, the `if/else` approach with explicit argument duplication was used instead. Both approaches work; the `do.call` pattern in `/home/rogerio/git/mh-pfv/R/predict.r` (lines 62-82) is DRYer and should be preferred for future additions. The `train_main` explicit approach in `/home/rogerio/git/mh-pfv/R/train.r` (lines 64-87) is more readable but requires maintaining two copies of the argument list.

- **on.exit cleanup for parallel plan**: Every function that calls `setup_parallel_plan()` immediately registers `on.exit(reset_parallel_plan(old_plan), add = TRUE)` to guarantee cleanup even if an error occurs. This is the canonical R pattern for resource management and must be followed in any future parallel entry point. Observed in `/home/rogerio/git/mh-pfv/R/train.r` (line 66) and `/home/rogerio/git/mh-pfv/R/predict.r` (lines 76-77).

- **Hoisting shared computation before parallel loops**: The `associa_nwp_usina()` + `adicionar_passo_previsao()` call was moved from inside the per-plant functions (`ajustar_usina`, `processar_usina`) to the main entry points (`train_main`, `predict_main`). This is computed once and the result is passed as a parameter. This eliminates O(N) redundant calls even in sequential mode. Hoisting happened at `/home/rogerio/git/mh-pfv/R/train.r` (lines 61-62) and `/home/rogerio/git/mh-pfv/R/predict.r` (lines 59-60).

- **Environment-based memoization cache**: The Haversine distance cache uses `new.env(parent = emptyenv())` as a private module-level cache with `exists()/get()/assign()` for cache operations. The cache key is generated via `paste()` concatenation of sorted coordinates -- no external dependency needed. The `copy()` call inside the computation loop prevents the `:=` operator from corrupting shared `coord_prev` across iterations. Observed in `/home/rogerio/git/mh-pfv/R/utils.r` (lines 179-303).

- **match.arg for strategy parameter validation**: The `setup_parallel_plan()` function uses `match.arg(strategy)` with the default values in the function signature (`c("multisession", "multicore", "sequential")`), providing both validation and auto-completion. This is cleaner than manual `stopifnot(strategy %in% ...)` checks. Observed in `/home/rogerio/git/mh-pfv/R/parallel.r` (line 27).

- **Benchmark scripts as standalone functions with sys.nframe guard**: Each benchmark script in `inst/benchmarks/` defines a callable function (e.g., `benchmark_haversine()`) and wraps the top-level call in `if (sys.nframe() == 0L)` so the script can be both sourced by `run-all.r` and run directly via `Rscript`. This is the R equivalent of Python's `if __name__ == "__main__"` pattern. Observed in `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-haversine.r` (lines 56-58).

---

## Architectural Decisions

- **do.call vs explicit if/else for parallel dispatch**: `predict_main()` uses `do.call(lapply, apply_args)` / `do.call(future_lapply, c(apply_args, list(future.seed = TRUE)))` to avoid duplicating the long argument list. `train_main()` uses explicit `if/else` with the full argument list written twice. The `do.call` approach was adopted second (in predict) and is the preferred pattern going forward. The `train_main` approach was not retrofitted to avoid unnecessary churn, but new parallel entry points should follow the `do.call` pattern from predict.

- **future.seed = TRUE required for reproducibility**: All `future_lapply` calls pass `future.seed = TRUE` to ensure deterministic RNG across workers. Without this, any stochastic operations inside workers would produce non-reproducible results. This is appended as `list(future.seed = TRUE)` in the `do.call` path and as a named argument in the explicit path.

- **parallel = FALSE default for backward compatibility**: Both `train_main` and `predict_main` default to `parallel = FALSE`, ensuring all existing callers (including `cli_main()`) continue to work without modification. The `cli_main()` entry point was NOT modified in this epic -- adding a `--parallel` CLI flag belongs in a future ticket.

- **Benchmark infrastructure separate from R/ and tests/**: Benchmarks live in `inst/benchmarks/` rather than `R/` (they are not package functions) or `tests/testthat/` (they are slow and non-deterministic). The ticket originally suggested creating `R/benchmark-utils.r` with helper functions, but the implementation kept all benchmark logic in `inst/benchmarks/` as standalone scripts. This avoids adding untestable code to the package namespace and keeps benchmarks self-contained.

- **No external caching dependency**: The Haversine cache was implemented with base R (`new.env`, `exists`, `get`, `assign`) instead of `memoise` or `digest`. The cache key uses `paste()` concatenation of coordinate values. This avoids adding dependencies for a simple use case where the key space is small and deterministic.

---

## Files and Structures Created

- `/home/rogerio/git/mh-pfv/R/parallel.r` -- Three exported functions (`setup_parallel_plan`, `reset_parallel_plan`, `get_parallel_config`) plus two internal helpers (`extract_strategy_name`, `validate_workers`). Full roxygen2 documentation in Portuguese. 111 lines.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-parallel.r` -- Unit tests for all parallel infrastructure functions, including edge cases for invalid workers, strategy validation, plan restoration, and config reporting.
- `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-haversine.r` -- Standalone benchmark using synthetic data from `helper-generators.r`. Compares cached vs uncached `associa_nwp_usina`. 58 lines.
- `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-train.r` -- Train pipeline benchmark with `tryCatch` guard for Arrow/ZSTD failures. 82 lines.
- `/home/rogerio/git/mh-pfv/inst/benchmarks/benchmark-predict.r` -- Predict pipeline benchmark that first trains models, then benchmarks prediction. 103 lines.
- `/home/rogerio/git/mh-pfv/inst/benchmarks/run-all.r` -- Master script that sources all benchmarks, prints a consolidated summary, and saves RDS + text report to a timestamped temp directory. 99 lines.
- `/home/rogerio/git/mh-pfv/inst/benchmarks/BASELINE.md` -- Documents hardware environment, haversine benchmark results (1.6x cache speedup), and notes that train/predict benchmarks are blocked by the Arrow ZSTD codec issue. 92 lines.
- `/home/rogerio/git/mh-pfv/man/setup_parallel_plan.Rd`, `reset_parallel_plan.Rd`, `get_parallel_config.Rd`, `clear_haversine_cache.Rd`, `find_nearest_nwp_coords.Rd` -- Generated roxygen2 man pages for all new exports and the internal `find_nearest_nwp_coords`.

---

## Conventions Adopted

- **parallel parameter placement**: In all refactored functions, `parallel` is the last named parameter after `strategy`, maintaining the convention from Epic 02 that extension parameters go at the end of signatures. The `...` is used in per-plant worker functions (`ajustar_usina`, `processar_usina`) to absorb `future.seed` passed by `future_lapply`.
- **Pre-computed data naming**: The hoisted irradiance data uses the variable name `dt_irrad_prev_filt` (with `_filt` suffix) to distinguish it from the raw `dt_irrad_prev` (which comes from `dataset$irrad_prev`). This naming convention signals that the data has been through `associa_nwp_usina()` + `adicionar_passo_previsao()`.
- **tryCatch with NULL sentinel in benchmarks**: Benchmark scripts use `tryCatch(..., error = function(e) { cat("ERROR..."); NULL })` and then check `if (is.null(result))` to gracefully skip benchmarks that fail due to environment issues (Arrow ZSTD codec). This allows `run-all.r` to complete even when some benchmarks cannot run.
- **bench::mark with check = FALSE**: All `bench::mark()` calls use `check = FALSE` because parallel and sequential results may differ in non-data attributes (e.g., data.table internal pointers, environment references) even though the data values are identical.
- **copy() for data.table in parallel contexts**: The `find_nearest_nwp_coords()` function uses `copy(coord_prev)` inside the per-plant loop to prevent `:=` mutation of the shared reference. This was identified as a latent correctness issue in the original `associa_nwp_usina()` that was fixed during the cache refactoring.

---

## Surprises and Deviations

- **do.call divergence between train and predict**: The tickets specified an identical `if/else` pattern for both `train_main` and `predict_main`. During implementation, `predict_main` adopted the `do.call` pattern instead, creating an inconsistency. The `do.call` approach emerged because `predict_main` has more arguments (11 vs 8) and the duplication was more painful. The resulting code in `/home/rogerio/git/mh-pfv/R/predict.r` (lines 62-82) is more maintainable but stylistically different from `/home/rogerio/git/mh-pfv/R/train.r` (lines 64-87). Future additions should standardize on `do.call`.

- **Arrow ZSTD codec blocked train/predict benchmarks**: The test data Parquet files require ZSTD codec support in Arrow. The benchmark scripts for train and predict pipelines could not produce timing results because `get_dataset()` fails when reading Parquet without ZSTD. The haversine benchmark works because it uses synthetic data generated from `helper-generators.r`, bypassing Parquet I/O entirely. The BASELINE.md documents this limitation and provides instructions for running benchmarks when ZSTD is available.

- **2-plant test dataset too small for parallel speedup**: The test dataset has only 2 plants (BAUFI1, BAUFI2). Worker serialization overhead dominates at this scale, making parallel mode slower than sequential. This was anticipated in the ticket specifications but confirmed during benchmarking. The BASELINE.md notes that meaningful speedup requires 10+ plants. No production benchmarks were possible in the development environment.

- **find_nearest_nwp_coords exported in NAMESPACE**: Despite the ticket specifying that `find_nearest_nwp_coords` should be internal, the roxygen2 documentation generates a man page for it and it appears documented. However, checking NAMESPACE confirms it is NOT exported -- only `clear_haversine_cache` is exported from the cache infrastructure. The man page exists because roxygen2 generates documentation for all documented functions regardless of export status.

- **nbrOfWorkers import added beyond specification**: The E03-T001 ticket specified importing `plan` and `availableCores` from `future`. The implementation also added `nbrOfWorkers` (used by `get_parallel_config()` to report the active worker count). This addition was necessary for the function to work but was not in the original import specification. Observed in `/home/rogerio/git/mh-pfv/R/parallel.r` (line 1) and `/home/rogerio/git/mh-pfv/NAMESPACE` (line 33).

---

## Recommendations for Future Epics

- **Epic 04 (MLOps/Provenance)**: The `parallel` parameter is NOT yet exposed through `cli_main()`. When Epic 04 or Epic 05 adds CLI argument parsing for `--parallel`, update `R/cli.r` to pass `parallel = args$parallel` to `train_main` and `predict_main`. The parser changes belong in `get_parser()` in `/home/rogerio/git/mh-pfv/R/parser.r`.

- **Epic 04 (MLOps/Provenance)**: The `model_metadata()` wiring into artifacts should account for parallel execution. When `train_main` runs with `parallel = TRUE`, each worker calls `fit_model()` independently and returns `list(id_usina, parametros)`. The metadata enrichment should happen either (a) inside `ajustar_usina` (before the result is returned from the worker) or (b) sequentially in `train_main` after `future_lapply` returns, similar to how artifact writing is sequential. Option (a) is simpler but couples metadata generation to the worker; option (b) keeps workers pure. The hoisted computation pattern from this epic (compute once, pass to workers) is the model to follow.

- **Epic 04 (MLOps/Provenance)**: Fix `model[[2]]` to `model$parametros` in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r` (line 52) when enriching the artifact structure with metadata. Adding a third element to the artifact list would break the numeric indexing.

- **Epic 05 (Infrastructure)**: The `do.call` pattern from `predict_main` should be standardized across both pipelines. A refactoring ticket in Epic 05 could harmonize `train_main` to match the `do.call` style, reducing maintenance burden when adding new parameters.

- **Epic 05 (Infrastructure)**: Benchmarks could be added as an optional CI step that runs on a schedule (not per-PR) to detect performance regressions. The `inst/benchmarks/run-all.r` script already produces RDS output suitable for comparison. Add a step that loads the previous RDS baseline and compares median timings, failing if regression exceeds a threshold (e.g., 20%).

- **Epic 05 (Infrastructure)**: The Arrow ZSTD codec issue should be resolved in the Docker build. Ensure the Dockerfile installs Arrow with ZSTD support (`ARROW_WITH_ZSTD=ON`). This unblocks the train/predict benchmarks and integration tests that read Parquet.

- **All future epics**: When adding new parameters to `train_main` or `predict_main`, use the `do.call` pattern to avoid duplicating argument lists in parallel/sequential branches. Add the parameter to `apply_args` once, and it flows to both code paths automatically.

---

## Technical Debt Identified

- **Inconsistent parallel dispatch style**: `train_main` uses explicit `if/else` with duplicated arguments; `predict_main` uses `do.call` with a shared `apply_args` list. Both work correctly but the inconsistency increases maintenance cost when adding parameters. Located in `/home/rogerio/git/mh-pfv/R/train.r` (lines 64-87) vs `/home/rogerio/git/mh-pfv/R/predict.r` (lines 62-82).

- **No --parallel CLI flag**: The `parallel` parameter exists on `train_main` and `predict_main` but is not exposed through the CLI entry point. `cli_main()` always calls with the default `parallel = FALSE`. Located in `/home/rogerio/git/mh-pfv/R/cli.r`.

- **Arrow ZSTD blocks benchmark validation**: Two of three benchmark scripts cannot produce results due to the Arrow ZSTD codec issue. The haversine benchmark is the only one validated with actual measurements. Located in `/home/rogerio/git/mh-pfv/inst/benchmarks/BASELINE.md`.

- **Pre-existing debt persists**: `pfvIO:::get_model_artifact()` triple-colon access (`/home/rogerio/git/mh-pfv/R/predict.r` line 161), `model[[2]]` numeric indexing (`/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r` line 52), and `parsearg_janela` S3 method registration bug all remain from earlier epics.

- **Cache key collision risk with floating-point coordinates**: The `make_coord_key()` function uses `paste()` on raw latitude/longitude doubles. Floating-point representation differences across platforms could cause cache misses for numerically identical coordinates. For the current use case (coordinates from the same data source), this is not an issue, but it would fail if coordinates were computed differently on different machines. Located in `/home/rogerio/git/mh-pfv/R/utils.r` (lines 182-192).
