# Accumulated Learnings Summary -- Through Epic 04

**Last Updated**: 2026-02-22
**Epics Completed**: 4 (Quality Foundation, Extensibility Refactor, Performance and Parallelization, MLOps and Provenance)

## Test Infrastructure

- Test data at `tests/testthat/data/` covers July--September 2025 with 2 plants (BAUFI1, BAUFI2)
- Every test calling `parse_config()` must use `janela = list("2025-07-01", "2025-09-30")` -- `list()` not `c()`
- Factory functions in `tests/testthat/helper-generators.r` provide `gen_model_artifact()` (enriched, with metadata) and `gen_model_artifact_legacy()` (old format, no metadata); both are needed for backward-compatibility tests
- Use `withr::local_tempdir()` for temp directories; `skip_if_not(dir.exists(test_path("data")))` for dataset-dependent tests
- Mock S3 methods require `registerS3method("generic", "class", fn, envir = asNamespace("mhpfv"))` for dispatch
- Snapshot tests in `_snaps/snapshot-regression.md` are the primary regression safety net
- Parallel tests must call `withr::defer(future::plan("sequential"))` to avoid leaking plan state
- Internal functions are tested via `mhpfv:::fn()` triple-colon access (e.g., `mhpfv:::write_checkpoint`, `mhpfv:::cleanup_checkpoint` in `tests/testthat/test-provenance.r`)
- `lgr` log messages do NOT propagate as R conditions -- `expect_warning()` will not catch them; use `expect_no_warning()` only to confirm no R-level warning is raised

## I/O Layer

- All pipeline data access routes through `pfvIO::conectamock_pfv(datadir)` creating a filesystem-backed connection
- `pfvIO:::get_model_artifact()` (triple colon) is used in `R/predict.r` line 203 -- fragile coupling to pfvIO internals
- Arrow Parquet files require ZSTD support (`ARROW_WITH_ZSTD=ON`) for test data reads; blocks train/predict integration benchmarks
- Model artifacts are now `list(id_usina, parametros, metadata)` as RDS; enriched by `build_model_artifact()` in `R/artifact.r`
- Provenance and checkpoint files are JSON; intermediate per-plant predict results are RDS (`plant-result-{id_usina}.rds`)
- All file-writing operations in `R/provenance.r` are wrapped in `tryCatch` so I/O failures never crash the pipeline

## Architecture After Epic 04

- `R/cli.r::cli_main(datadir)` dispatches to `train_main(config)` or `predict_main(config)`; does NOT expose `parallel` or `resume` flags yet
- Both pipelines now accept `parallel = FALSE` and `resume = FALSE` as parameters; `resume = TRUE` triggers checkpoint-based plant skipping
- Artifact enrichment happens inside `ajustar_usina()` in `R/train.r` (line 157) via `build_model_artifact(iu, regressoes, strategy, config)` -- not in the post-loop write phase
- Provenance is registered with `on.exit(..., add = TRUE)` BEFORE the parallel plan cleanup so it runs AFTER (LIFO) in `R/train.r` lines 57-62 and `R/predict.r` lines 58-63
- `<<-` is used in `lapply` callbacks to update provenance in enclosing scope; documented with inline comments in both `R/train.r` line 110 and `R/predict.r` line 107
- Checkpoint files are written after each artifact write (sequential phase only); never from inside `future_lapply` workers

## Strategy Pattern Conventions

- Constructor: `new_model_strategy(type, ...)` creates `c(type, "model_strategy")` dual-class object
- Each strategy type gets a convenience constructor (e.g., `linear_regression_strategy()`) in `model-<type>.r`
- Adding a new strategy: create 1 file with 4 functions (constructor + 3 methods) -- no existing files modified
- `strategy` is always the second-to-last named parameter; `parallel` and `resume` come after

## MLOps / Provenance Conventions

- Config identity is determined by `normalize_config_for_hash()` in `R/artifact.r` (line 50), which selects fields from `get_config_hash_keys()` (line 58-64) and sorts them; the same hash is used in both artifact metadata and provenance records
- Provenance record fields: `run_id`, `mode`, `package_version`, `r_version`, `start_time`, `end_time`, `duration_seconds`, `config_hash`, `n_plants`, `plant_ids`, `plant_status`, `parallel`, `status`
- File naming: `provenance-{run_id}.json` (permanent), `checkpoint-{run_id}.json` (ephemeral, deleted on success), `plant-result-{id_usina}.rds` (ephemeral, deleted on success)
- `cleanup_checkpoint()` in `R/provenance.r` is internal (not exported); exposed only via `mhpfv:::` for tests
- Backward compatibility: old-format artifacts (no `metadata`) accepted with lgr warning everywhere; check via `"metadata" %in% names(artifact)` -- no format migration triggered

## Parallelism Conventions

- `parallel = FALSE` default on all entry points for backward compatibility
- `future.seed = TRUE` required on all `future_lapply` calls for reproducibility
- Artifact writing remains sequential (filesystem race condition avoidance)
- Checkpoint writing also remains sequential -- never from parallel workers
- Strategy objects are plain S3 lists -- safe to serialize to workers without special handling
- `copy()` on data.table objects passed to workers where `:=` mutation could occur

## Validation Framework

- `validate_input(dt, schema_name)` checks columns, types, and key NAs; collects ALL errors before raising
- `validate_artifact(artifact)` in `R/artifact.r` follows the same error-collection pattern via private helpers `check_artifact_id_usina`, `check_artifact_parametros`, `check_artifact_metadata`
- Exported but NOT wired into pipeline (opt-in); same stance as Epic 02

## Code Conventions

- All column names, error messages, and log messages in Portuguese
- Tests use nested `test_that()` blocks: outer asserts `is.function(f)`, inner blocks test behaviors
- data.table exclusively; `copy()` calls at strategy and parallel boundaries; `unname()` on named vectors before passing to `data.table()` constructor to prevent unexpected column names
- `format_comparison()` and `compare_artifacts()` in `R/model-comparison.r` are decomposed into small private helpers -- each helper is testable in isolation; follow this decomposition pattern for new functions over 30 lines

## Known Technical Debt

- `parsearg_janela.character` S3 method not registered in NAMESPACE (pre-existing)
- `pfvIO:::get_model_artifact()` triple-colon access (pre-existing)
- `R/zzz.r` lifecycle hooks permanently uncoverable by covr (~0.8% gap)
- Validation schemas hardcoded; no sync mechanism with pfvIO column formats
- Inconsistent parallel dispatch style: `train_main` (explicit if/else) vs `predict_main` (do.call)
- No `--parallel` or `--resume` CLI flags in `cli_main()`
- Cache key uses raw `paste()` on floats -- platform-dependent representation risk
- `attr(diffs, "timestamp_a")` in `compare_metadata()` (`R/model-comparison.r` lines 188-189) -- attributes lost on JSON serialization; must change to named list elements if comparison results are ever serialized
- `read_checkpoint()` orders by `file.mtime()` -- unreliable on network filesystems; more robust to parse timestamp from run ID in filename
- Per-plant intermediate results (`plant-result-*.rds`) are written only when `resume = TRUE`; a crash during a non-resume predict run leaves no resumable state

## Recommendations for Next Epics

- Epic 05: Add `--resume` flag to CLI parser in `R/parser.r`, wire through `cli_main()` to `train_main`/`predict_main` -- parameter already exists on both functions
- Epic 05: Standardize `train_main` to use `do.call` pattern matching `predict_main` for parallel dispatch
- Epic 05: Resolve Arrow ZSTD in Docker build to unblock train/predict integration benchmarks
- Epic 05: If a CLI `mhpfv cleanup` command is added, export `cleanup_checkpoint()` from NAMESPACE
- Epic 05: Add a test verifying `get_config_hash_keys()` key set matches the expected config schema keys
- Epic 06: `provenance-{run_id}.json` files are the natural feed for health reports -- fields `duration_seconds`, `n_plants`, `status`, `plant_status` are ready to aggregate
- Epic 06: All provenance/checkpoint log messages use `lgr::get_logger("mhpfv")` -- configure appenders on this logger, not a new name
- Epic 06: `plant_status` in provenance JSON enables per-plant failure rate analysis across multiple runs
