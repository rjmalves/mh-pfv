# Epic 06 Learnings: Observability and Monitoring

**Date**: 2026-02-22
**Epics in Scope**: E06-T001 (Structured Logging), E06-T002 (Pipeline Metrics), E06-T003 (Health Report)

---

## Patterns Established

- **FilterInject over set_fields for log context**: The ticket spec suggested `lgr::logger$set_fields()` for attaching run context. The implementation used `lgr::FilterInject$new(run_id = ..., mode = ...)` instead, attached to the logger by name (`"mhpfv_ctx"`). This is superior because `FilterInject` injects fields into log events without mutating logger-level state permanently, is idempotent when removed/re-added by name, and its `$values` field is directly inspectable in tests without capturing log output. See `R/logging.r:set_log_context()`.

- **Named filter for context lifecycle management**: `set_log_context()` first removes any existing `"mhpfv_ctx"` filter before adding a new one. This prevents filter accumulation across repeated calls (e.g., in test loops). The helper `get_ctx_filter_name()` centralizes the magic string. See `R/logging.r:59-65`.

- **Parallel batch timing with estimated per-plant division**: For parallel `future_lapply` executions, per-plant timing is impossible without worker communication overhead. The implementation captures wall-clock `proc.time()[["elapsed"]]` around the entire batch and divides by plant count, recording the estimate for each plant. This is explicitly documented in code with `est_per_plant`. See `R/train.r:92-99` and `R/predict.r:103-110`.

- **Sequential sequential-path timing with `<<-` update**: In the sequential code path, each `ajustar_usina` call is wrapped in an anonymous function that records `proc.time()` before and after, then updates `metrics` in the enclosing scope via `<<-`. This is the same scoping pattern used for `provenance <<-` in prior epics. See `R/train.r:100-118`.

- **tryCatch I/O wrapper pattern extended to all observability writes**: `write_metrics()` and `write_health_report()` both follow the exact pattern of `write_provenance()` -- a single `tryCatch` wrapping directory creation + JSON serialization + file write, with an `lg$warn(...)` on error and `invisible(filepath)` return. See `R/metrics.r:142-164` and `R/health-report.r:82-104`.

- **Health classification via decomposed private helpers**: `build_health_report()` delegates to `build_plant_reports()`, `classify_plant_health()`, `classify_overall_health()`, `collect_warnings()`, and `collect_errors()`. Each function is independently testable and accessed via `mhpfv:::` in tests. This continues the decomposition pattern from `R/model-comparison.r`. See `R/health-report.r`.

- **Test fixture generators for health report tests**: `tests/testthat/test-health-report.r` defines four local generator functions (`gen_provenance_completed`, `gen_provenance_failed`, `gen_metrics_healthy`, `gen_metrics_high_na`, `gen_metrics_low_slots`) at the top of the file. These serve as compact, self-describing test fixtures and avoid repeated boilerplate inside each `test_that` block.

- **`character(0L)` for empty warning/error arrays**: The `warnings` and `errors` fields in the health report are `character(0L)` when empty. `jsonlite::toJSON` with `auto_unbox = TRUE` correctly serializes this as `[]` in JSON. Converting to `list()` would produce incorrect output. Verified in test: `test-health-report.r:602-611`.

---

## Architectural Decisions

- **FilterInject instead of set_fields**: `$set_fields()` modifies the logger's persistent field list and interacts poorly with parallel workers and test isolation. `FilterInject` operates at the event level, is removable by name, and leaves no persistent state on the logger object. Rejected alternative: `$set_fields()` with `$remove_fields()` as specified in the ticket.

- **No `stage` field in pipeline usage**: While `set_log_context()` accepts a `stage` parameter, `train_main()` and `predict_main()` only call it with `run_id` and `mode`. Stage-level logging (e.g., "data-loading", "fitting", "writing") was not wired into the pipeline -- the parameter exists for future use but is not surfaced in production log lines.

- **predict.r sequential path refactored to explicit lapply**: The pre-existing `do.call(lapply, apply_args)` pattern in `predict_main()`'s sequential path was replaced with an explicit `lapply(v_usinas_pending, function(iu) { ... })` to enable per-plant timing with `proc.time()`. The parallel path retains `do.call(future.apply::future_lapply, ...)`. This partially resolves the "inconsistent parallel dispatch style" noted as technical debt in Epic 05.

- **on.exit ordering: clear_log_context first, then provenance/metrics/health**: Two `on.exit` registrations are used in `train_main()` and `predict_main()`. The first (registered immediately after `set_log_context`) calls `clear_log_context()`. The second (registered after resume logic) finalizes and writes provenance, metrics, and health report. Because `on.exit` with `add = TRUE` uses LIFO ordering, the health report write happens before context clearing, which is the desired order. See `R/train.r:44,61-70`.

- **Health report built from in-memory objects, not from disk**: `build_health_report()` receives in-memory `provenance` and `metrics` lists from the pipeline's `on.exit` block. It does NOT read from `provenance-{run_id}.json` or `metrics-{run_id}.json` files. This avoids I/O and serialization round-trips but means the health report reflects the in-memory state at exit time.

---

## Files and Structures Created

- `R/metrics.r` -- Pipeline metrics collection: `create_metrics()`, `record_plant_timing()`, `record_plant_data_volume()`, `record_model_quality()`, `finalize_metrics()`, `write_metrics()`. All internal (no `@export`). Writes `metrics-{run_id}.json`.

- `R/health-report.r` -- Health report generation: `build_health_report()`, `classify_plant_health()`, `classify_overall_health()`, `write_health_report()`, plus private helpers `build_plant_reports()`, `collect_warnings()`, `collect_errors()`. All internal except `build_health_report` and `write_health_report` (documented but not exported). Writes `health-{run_id}.json`.

- `tests/testthat/test-logging.r` -- Tests for `logger_setup()`, `get_pkg_logger()`, `set_log_context()`, `clear_log_context()`, `configure_json_logging()`. Uses `mhpfv:::` access for internal functions. Uses `withr::local_envvar()` for all env var manipulation.

- `tests/testthat/test-metrics.r` -- Tests for all six metrics functions. Includes roundtrip JSON serialization test and `NA_real_` -> `null` serialization verification.

- `tests/testthat/test-health-report.r` -- Tests for all health report functions plus local fixture generators. Covers boundary conditions: `na_rate = 0.5` edge case, `metrics = NULL` graceful handling, empty `warnings`/`errors` JSON serialization.

- Man pages generated for all new documented functions: `man/set_log_context.Rd`, `man/clear_log_context.Rd`, `man/configure_json_logging.Rd`, `man/create_metrics.Rd`, `man/record_plant_timing.Rd`, `man/record_plant_data_volume.Rd`, `man/record_model_quality.Rd`, `man/finalize_metrics.Rd`, `man/write_metrics.Rd`, `man/build_health_report.Rd`, `man/classify_overall_health.Rd`, `man/classify_plant_health.Rd`, `man/write_health_report.Rd`.

---

## Conventions Adopted

- **Wall-clock timing via `proc.time()[["elapsed"]]`**: Do NOT use `system.time()` (captures CPU time). Use `proc.time()[["elapsed"]]` directly for wall-clock duration. Both `R/train.r` and `R/predict.r` follow this pattern.

- **Metrics updated with `<<-` in anonymous lapply functions**: When accumulating per-plant metrics inside `lapply(seq_along(v_usinas), function(i) { ... })`, `metrics <<-` is used to propagate updates to the enclosing scope. Same pattern as `provenance <<-` from Epic 04. Always accompanied by the inline comment `# <<- necessario para atualizar metrics no escopo pai`.

- **Observability output file naming**: Three JSON files are written per run, all in the same directory: `provenance-{run_id}.json`, `metrics-{run_id}.json`, `health-{run_id}.json`. The consistent `{type}-{run_id}.json` naming makes glob patterns straightforward.

- **Integer coercion for count fields**: `n_rows` and `n_na` in `record_plant_data_volume()` accept numeric inputs but are stored as `as.integer(n_rows)` to produce clean integer JSON values (not `1440.0`). This is necessary because predict result row counts come from `nrow()` which returns integer, but defensive coercion prevents type issues from other callers.

- **`suppressWarnings()` on `dir.create()` in `write_health_report()`**: `write_health_report()` uses `suppressWarnings(dir.create(...))` while `write_metrics()` uses plain `dir.create(...)`. This minor inconsistency exists and is acceptable; both are inside `tryCatch`.

- **Health thresholds**: NA rate threshold is `> 0.5` (strictly greater than 50%, so exactly 50% is `"healthy"`). Valid slots threshold is `< n_slots * 0.5` (strictly less than half). Both boundary conditions are verified in tests.

---

## Surprises and Deviations

- **`lgr::set_fields()` API divergence**: The ticket's implementation guide proposed `lg$set_fields(fields)` and `lg$set_fields(NULL)` for context management. In practice, `set_fields` modifies the logger's persistent `fields` R6 object, which does not support named removal of individual fields. Using `FilterInject` named `"mhpfv_ctx"` is the idiomatic lgr approach for injectable context. The resulting implementation in `R/logging.r:set_log_context()` is more robust but diverges from the ticket's code sample.

- **Parallel dispatch style not fully unified**: Epic 05 learnings recommended unifying `train_main`'s explicit `if/else` with `predict_main`'s `do.call` pattern. Epic 06 partially addressed this by refactoring the sequential path of `predict_main` to an explicit `lapply` (needed for per-plant timing). The parallel paths still differ: `train_main` uses an explicit `if (parallel) { future_lapply(...) } else { lapply(...) }` block, while `predict_main` uses `do.call(future.apply::future_lapply, ...)` for the parallel path. This inconsistency remains.

- **`renv.lock` expanded with `future` and `codetools`**: The renv snapshot acquired `future` (v1.69.0) and `codetools` (v0.2-20) during this epic's development. These are transitive dependencies of `future.apply` that were not previously locked. No new direct dependencies were added.

- **Man pages generated for internal functions without `@export`**: Several new internal functions (`classify_plant_health`, `classify_overall_health`, `build_health_report`, `write_health_report`, all metrics functions) received roxygen2 docblocks without `@export`. This generates `.Rd` files under `man/` but does not add entries to `NAMESPACE`. This is consistent with prior epics but creates `man/` clutter for functions that users cannot call directly.

- **No per-plant health report integration test**: The integration tests for `train_main` and `predict_main` verify that `metrics-{run_id}.json` exists and contains the expected structure, but neither integration test verifies that `health-{run_id}.json` is produced. This gap exists because the health report integration test was not added to `test-integration-train.r` or `test-integration-predict.r`. The health report is covered by unit tests only.

---

## Technical Debt Remaining

- **Inconsistent parallel dispatch style in train_main vs predict_main**: `R/train.r` uses explicit `if/else` for parallel/sequential branching; `R/predict.r` uses `do.call(future_lapply, ...)` for parallel and now uses explicit `lapply` for sequential. These should be unified into a single pattern in a future refactor.

- **`stage` field in `set_log_context()` is unused**: The `stage` parameter in `set_log_context()` is available and tested, but never set by any pipeline code. If stage-level logging is wanted in the future, callers in `train_main()`/`predict_main()` would need to call `set_log_context()` multiple times with different stage values.

- **No health report in integration tests**: `tests/testthat/test-integration-train.r` and `tests/testthat/test-integration-predict.r` verify metrics files but not health report files. A future test should assert that `health-{run_id}.json` exists and that `overall_health` is `"healthy"` for a successful run.

- **`man/` pages for non-exported functions**: `man/classify_plant_health.Rd`, `man/classify_overall_health.Rd`, and several others document internal functions. `R CMD check` may generate NOTEs about undocumented exports or documented non-exports depending on version. This should be cleaned up by either removing docblocks from purely internal helpers or converting them to `@keywords internal` with `@noRd`.

- **Per-plant timing in parallel mode is an estimate**: For parallel runs, `metrics-{run_id}.json` shows all plants with identical `duration_seconds` (the batch total divided by plant count). There is no note in the JSON output that these are estimates. A `timing_method` field (`"measured"` vs `"estimated_batch_average"`) would improve observability.

- **`parsearg_janela.character` unregistered S3 method**: Carried from Epic 01; not related to this epic but still unresolved.

---

## Recommendations for Future Work

- Add `health-{run_id}.json` existence and `overall_health` assertion to integration tests in `tests/testthat/test-integration-train.r` and `tests/testthat/test-integration-predict.r`.

- Add a `timing_method` field to `record_plant_timing()` output (`"measured"` or `"estimated"`) to distinguish accurate per-plant timing from batch-divided estimates. See `R/metrics.r:record_plant_timing()`.

- Unify parallel dispatch style: convert `train_main()`'s explicit `if (parallel)` branch to use the same `do.call(future_lapply, apply_args)` pattern as `predict_main()`. See `R/train.r:89-119`.

- Consider adding `@noRd` to purely internal health report helpers (`build_plant_reports`, `collect_warnings`, `collect_errors`) to suppress man page generation without removing documentation. See `R/health-report.r:106-174`.

- The `configure_json_logging()` function accepts a logger as its first argument when called from `logger_setup()`, but the ticket specification showed it as no-argument. The current signature is correct and more testable; update ticket documentation to match if referenced in the future.
