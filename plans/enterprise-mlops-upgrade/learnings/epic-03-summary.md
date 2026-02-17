# Accumulated Learnings Summary -- Through Epic 03

**Last Updated**: 2026-02-17
**Epics Completed**: 3 (Quality Foundation, Extensibility Refactor, Performance and Parallelization)

## Test Infrastructure

- Test data at `tests/testthat/data/` covers July--September 2025 with 2 plants (BAUFI1, BAUFI2)
- Every test calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` -- `list()` not `c()`
- Factory functions in `tests/testthat/helper-generators.r` provide 9+ generators; benchmarks also source these for synthetic data
- Use `withr::local_tempdir()` for temp directories; `skip_if_not(dir.exists(test_path("data")))` for dataset-dependent tests
- Mock S3 methods require `registerS3method("generic", "class", fn, envir = asNamespace("mhpfv"))` for dispatch
- Snapshot tests in `_snaps/snapshot-regression.md` are the primary regression safety net
- Parallel tests must call `withr::defer(future::plan("sequential"))` to avoid leaking plan state

## I/O Layer

- All data access routes through `pfvIO::conectamock_pfv(datadir)` creating a filesystem-backed connection
- `pfvIO:::get_model_artifact()` (triple colon) is used in `R/predict.r` line 161 -- fragile coupling to pfvIO internals
- Arrow Parquet files require ZSTD support (`ARROW_WITH_ZSTD=ON`) for test data reads; this blocks train/predict benchmarks
- Model artifacts are `list(id_usina, parametros)` as RDS; format is NOT strategy-aware yet

## Architecture After Epic 03

- `R/cli.r::cli_main(datadir)` dispatches to `train_main(config)` or `predict_main(config)`; does NOT expose `parallel` flag yet
- Both pipelines accept `strategy` (default: `linear_regression_strategy()`) and `parallel` (default: `FALSE`) parameters
- NWP association (`associa_nwp_usina` + `adicionar_passo_previsao`) is hoisted before per-plant loops in both pipelines
- `train_main` uses explicit `if/else` for parallel dispatch (`R/train.r` lines 64-87)
- `predict_main` uses DRYer `do.call` pattern with shared `apply_args` list (`R/predict.r` lines 62-82)
- `on.exit(reset_parallel_plan(old_plan), add = TRUE)` guarantees cleanup in both pipelines
- Three parallel infrastructure functions exported from `R/parallel.r`: `setup_parallel_plan`, `reset_parallel_plan`, `get_parallel_config`
- Haversine cache in `R/utils.r` uses `new.env(parent = emptyenv())` with `paste()`-based keys; `clear_haversine_cache()` exported

## Strategy Pattern Conventions

- Constructor: `new_model_strategy(type, ...)` creates `c(type, "model_strategy")` dual-class object
- Each strategy type gets a convenience constructor (e.g., `linear_regression_strategy()`) in `model-<type>.r`
- Adding a new strategy: create 1 file with 4 functions (constructor + 3 methods) -- no existing files modified
- `strategy` is always the second-to-last named parameter; `parallel` is always last

## Parallelism Conventions

- `parallel = FALSE` default on all entry points for backward compatibility
- `future.seed = TRUE` required on all `future_lapply` calls for reproducibility
- Artifact writing remains sequential (filesystem race condition avoidance)
- Strategy objects are plain S3 lists -- safe to serialize to workers without special handling
- `copy()` on data.table objects passed to workers where `:=` mutation could occur

## Validation Framework

- `validate_input(dt, schema_name)` checks columns, types, and key NAs; collects ALL errors before raising
- 5 schemas: `geracao_observada`, `irradiancia_prevista`, `corte_observado`, `usinas`, `melhor_historico_geracao`
- Exported but NOT wired into pipeline (opt-in); can be reused for artifact/provenance validation in Epic 04

## Benchmarking Infrastructure

- Benchmark scripts in `inst/benchmarks/` as standalone functions with `sys.nframe() == 0L` guard
- `run-all.r` sources all benchmarks, prints summary, saves RDS + text report to timestamped temp directory
- Haversine benchmark: 1.6x cache speedup measured (20 plants, 7 days synthetic data)
- Train/predict benchmarks blocked by Arrow ZSTD -- scripts exist but produce no baseline numbers
- 2-plant test dataset too small for meaningful parallel speedup; 10+ plants needed

## Code Conventions

- All column names and error messages in Portuguese
- Tests use nested `test_that()` blocks: outer asserts `is.function(f)`, inner blocks test behaviors
- data.table exclusively; `copy()` calls at strategy and parallel boundaries
- New files: `parallel.r`, `model-strategy.r`, `model-<type>.r`, `validation.r`; benchmarks in `inst/benchmarks/`

## Known Technical Debt

- `parsearg_janela.character` S3 method not registered in NAMESPACE (pre-existing)
- `pfvIO:::get_model_artifact()` triple-colon access (pre-existing)
- `model[[2]]` hardcoded index in `preenche_geracao_unit` -- should be `model$parametros` (from Epic 02)
- `R/zzz.r` lifecycle hooks permanently uncoverable by covr (~0.8% gap)
- Validation schemas hardcoded; no sync mechanism with pfvIO column formats
- Inconsistent parallel dispatch style: `train_main` (explicit if/else) vs `predict_main` (do.call)
- No `--parallel` CLI flag in `cli_main()`
- Cache key uses raw `paste()` on floats -- platform-dependent representation risk

## Recommendations for Next Epics

- Epic 04: Wire `model_metadata()` into artifact structure; enrich either in workers or post-loop (prefer post-loop)
- Epic 04: Fix `model[[2]]` to `model$parametros` when enriching artifact structure
- Epic 04: Reuse `validate_input()` schemas for artifact/provenance validation
- Epic 05: Standardize `train_main` to use `do.call` pattern matching `predict_main`
- Epic 05: Add `--parallel` flag to CLI parser in `R/parser.r` and wire through `cli_main`
- Epic 05: Resolve Arrow ZSTD in Docker build to unblock train/predict benchmarks
- Epic 05: Raise CI threshold from 75% to 80% once coverage stabilizes
- Epic 05: Consider scheduled CI benchmark runs using `inst/benchmarks/run-all.r` with regression detection
