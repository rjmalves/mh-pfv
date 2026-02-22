# Accumulated Learnings Summary -- Through Epic 06 (FINAL)

**Last Updated**: 2026-02-22
**Epics Completed**: 6 of 6 (Quality Foundation, Extensibility Refactor, Performance and Parallelization, MLOps Provenance, Infrastructure Hardening, Observability and Monitoring)

## Test Infrastructure

- Test data at `tests/testthat/data/` covers July--September 2025 with 2 plants (BAUFI1, BAUFI2)
- Every test calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` -- `list()` not `c()`
- Factory functions in `tests/testthat/helper-generators.r`: `gen_model_artifact()`, `gen_model_artifact_legacy()`, `gen_config()`; E06 added `gen_provenance_*` and `gen_metrics_*` as local generators in `test-health-report.r`
- Use `withr::local_tempdir()` for temp directories; `skip_if_not(dir.exists(test_path("data")))` for dataset-dependent tests
- Use `withr::local_envvar()` for all environment variable manipulation; `withr` must be in `DESCRIPTION` Suggests
- Internal functions tested via `mhpfv:::fn()` triple-colon access; mock S3 methods require `registerS3method(..., envir = asNamespace("mhpfv"))`
- Snapshot tests in `_snaps/snapshot-regression.md` are the primary regression safety net; parallel tests must defer `future::plan("sequential")`
- `lgr` messages do NOT propagate as R conditions -- verify log context by inspecting `lgr::get_logger("mhpfv")$filters$mhpfv_ctx$values`
- Tests use nested `test_that()` blocks: outer asserts `is.function(f)`, inner blocks test each behavior

## I/O Layer

- All data access routes through `pfvIO::conectamock_pfv(datadir)`; `pfvIO:::get_model_artifact()` triple-colon access in `R/predict.r` is pre-existing fragile coupling
- Arrow Parquet files require ZSTD support; `ARROW_WITH_ZSTD=ON` and `libzstd-dev` set in `Dockerfile`
- Model artifacts are `list(id_usina, parametros, metadata)` as RDS; enriched by `build_model_artifact()` in `R/artifact.r`
- File naming convention: `{type}-{run_id}.json` -- three JSON files per run in same directory: `provenance-`, `metrics-`, `health-`
- All file-writing operations wrapped in `tryCatch` -- I/O failures log a warning and never crash the pipeline (`write_provenance`, `write_metrics`, `write_health_report`)

## Architecture

- `R/cli.r::cli_main()` dispatches to `train_main(config, parallel, resume)` or `predict_main(config, parallel, resume)`; priority chain: CLI flag > `MHPFV_*` env var > hardcoded default; `!isTRUE(param)` is the correct gate
- `MHPFV_PARALLEL`, `MHPFV_RESUME`, `MHPFV_WORKERS` declared as `ENV` defaults in `Dockerfile` runtime stage; `cli_main()` logs their resolved and raw values at startup
- Provenance and observability records registered with `on.exit(..., add = TRUE)` BEFORE parallel plan cleanup (LIFO ensures writes happen before plan reset)
- `<<-` used in `lapply` callbacks to update `provenance` and `metrics` in enclosing scope; always annotated with inline comment

## Observability Stack

- Run context injected via `lgr::FilterInject` named `"mhpfv_ctx"` (NOT `$set_fields()`) -- removable by name, inspectable via `$values`; see `R/logging.r:set_log_context()`
- JSON log format activated by `MHPFV_LOG_FORMAT=json`; default remains human-readable `LayoutFormat`; `stage` parameter in `set_log_context()` exists but is not yet used by pipeline code
- Per-plant progress logged as `lg$info("Usina %s concluida (%d/%d)", iu, i, n_total)` in both pipelines
- Metrics file `metrics-{run_id}.json`: per-plant timing, data volume (predict mode), model quality (train mode), pipeline aggregates; see `R/metrics.r`
- Health report `health-{run_id}.json`: `overall_health` (`"healthy"`, `"degraded"`, `"failed"`), per-plant classification, Portuguese `warnings`/`errors` arrays; see `R/health-report.r`
- Health thresholds: NA rate `> 0.5` = warning; valid slots `< n_slots * 0.5` = warning; boundary values are healthy (strict inequality)
- Per-plant timing in parallel mode is an estimate (`batch_elapsed / n_plants`); sequential mode uses `proc.time()[["elapsed"]]` per call

## Docker / Infrastructure Conventions

- Two-stage Dockerfile: builder `rocker/r-ver:4.5.2` with renv restore; runtime copies R library paths only
- `RENV_CONFIG_REPOS_OVERRIDE="https://p3m.dev/cran/__linux__/noble/latest"` routes CRAN to PPM pre-built binaries; runtime requires `libcurl4-openssl-dev`, `libssl-dev`, `libzstd-dev`, `python3`
- All five CI workflows use `concurrency` with `cancel-in-progress: true`; `test-coverage.yaml` enforces 75% threshold; `docker.yaml` uses GHA layer caching

## Strategy Pattern Conventions

- Constructor: `new_model_strategy(type, ...)` creates `c(type, "model_strategy")` dual-class object; adding a strategy = 1 new file, no existing files modified
- `strategy` is always the second-to-last named parameter; `parallel` and `resume` come after

## MLOps / Provenance Conventions

- Config identity via `normalize_config_for_hash()` in `R/artifact.r`; same hash in artifact metadata and provenance record
- Provenance fields: `run_id`, `mode`, `package_version`, `r_version`, `start_time`, `end_time`, `duration_seconds`, `config_hash`, `n_plants`, `plant_ids`, `plant_status`, `parallel`, `status`
- Backward compatibility: old-format artifacts (no `metadata`) accepted with lgr warning; check via `"metadata" %in% names(artifact)`

## Parallelism Conventions

- `parallel = FALSE` default on all entry points; `future.seed = TRUE` required on all `future_lapply` calls
- Artifact, checkpoint, metrics, and health report writes remain sequential -- never from parallel workers
- Strategy objects are plain S3 lists; `copy()` on data.table objects passed to workers where `:=` mutation could occur

## Code Conventions

- All column names, error messages, log messages, and report strings in Portuguese
- data.table exclusively; `copy()` at strategy and parallel boundaries; `unname()` on named vectors before `data.table()` constructor
- Non-exported helpers documented with roxygen2 (no `@export`); internal access via `mhpfv:::`; decompose functions over ~30 lines into private helpers
- `character(0L)` for empty string vectors (not `list()`); `as.integer()` for count fields; `stopifnot()` for input validation

## Known Technical Debt

- `parsearg_janela.character` S3 method not registered in NAMESPACE; `pfvIO:::get_model_artifact()` triple-colon access (both pre-existing)
- `R/zzz.r` lifecycle hooks permanently uncoverable by covr (~0.8% gap)
- Inconsistent parallel dispatch style: `train_main` uses explicit `if/else`; `predict_main` uses `do.call` for parallel path -- not unified
- `stage` field in `set_log_context()` tested but never called with non-NULL value by pipeline code
- No `health-{run_id}.json` assertion in integration tests (`test-integration-train.r`, `test-integration-predict.r`)
- Per-plant timing in parallel mode is a batch-divided estimate with no `timing_method` indicator in the JSON output
- Internal-only helpers (`classify_plant_health`, `build_plant_reports`, etc.) generate `man/*.Rd` files without `@noRd`; may produce `R CMD check` NOTEs
- Cache key uses raw `paste()` on floats in `R/utils.r` (platform float representation risk); `read_checkpoint()` orders by `file.mtime()` (unreliable on network filesystems)
