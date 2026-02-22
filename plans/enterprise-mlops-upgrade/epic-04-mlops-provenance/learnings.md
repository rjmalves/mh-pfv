# Epic 04 Learnings -- MLOps and Provenance

**Epic**: epic-04-mlops-provenance
**Tickets**: E04-T001, E04-T002, E04-T003, E04-T004
**Date Extracted**: 2026-02-22

---

## Patterns Established

### Enriched Artifact Pattern

- Model artifacts were extended from `list(id_usina, parametros)` to `list(id_usina, parametros, metadata)` by adding a `build_model_artifact()` factory in `/home/rogerio/git/mh-pfv/R/artifact.r`.
- Backward compatibility is preserved through `validate_artifact()`, which warns via lgr when metadata is absent rather than erroring. Predefined constants `get_config_hash_keys()` in `R/artifact.r` make the normalized config set explicit and testable.
- The enrichment happens at the boundary where the result is constructed (`ajustar_usina()` in `R/train.r` line 157) rather than post-hoc in the artifact-writing loop, meaning workers receive `config` as a named parameter (not via `...`).

### Config Hash Normalization Pattern

- `normalize_config_for_hash()` in `R/artifact.r` (line 50) selects a fixed subset of relevant config keys and sorts them alphabetically before hashing with `digest::digest(..., algo = "sha256")`. This guarantees deterministic hashing regardless of insertion order.
- The same helper is called from both `R/artifact.r` and `R/provenance.r`, avoiding code duplication. The key list lives in `get_config_hash_keys()` in `R/artifact.r` and is the single point of truth for what constitutes "training configuration identity."

### Provenance Record Pattern

- All provenance state is held in a plain R list (not an S3 object or environment) for transparency and easy JSON serialization. Functions `create_provenance`, `update_plant_status`, and `finalize_provenance` follow a pure functional style -- each returns a new list, never mutates in place.
- The `<<-` assignment pattern is explicitly used and documented in `R/train.r` line 110 and `R/predict.r` line 108 when updating provenance from within `lapply` callbacks: `provenance <<- update_plant_status(...)`. This is the standard R idiom for accumulating state in closures.

### Resilient I/O Pattern

- All file-writing operations for provenance and checkpoints (`write_provenance`, `write_checkpoint`, `write_plant_result`, `cleanup_checkpoint` in `R/provenance.r`) are wrapped in `tryCatch` with lgr warnings. The pipeline must never fail because of observability I/O failures.
- `dir.create(..., recursive = TRUE)` is called defensively inside each writer before writing. This avoids silent failures when the output directory does not exist.

### Timestamp Serialization Pattern

- `jsonlite::toJSON()` serializes `POSIXct` as epoch integers by default. A dedicated helper `format_provenance_timestamps()` in `R/provenance.r` (line 195) converts both `start_time` and `end_time` to ISO 8601 strings before handing the list to `toJSON`. This helper is reused by both `write_provenance` and `write_checkpoint`.

### on.exit Stacking for Pipeline Cleanup

- Both `train_main` and `predict_main` register the provenance finalizer as the first `on.exit` handler (before the parallel plan cleanup) using `add = TRUE`. Because R evaluates `on.exit` handlers in LIFO order, the provenance write runs last -- after parallel resources are released -- which is the correct ordering. See `R/train.r` lines 57-62 and `R/predict.r` lines 58-63.

### Model Comparison: Functional Decomposition

- `compare_artifacts()` in `R/model-comparison.r` decomposes into small private helpers (`compare_metadata`, `compare_coefficients`, `summarize_coefficient_diff`, `warn_cross_type`), each testable in isolation.
- `format_comparison()` is similarly split into four helpers (`format_comparison_header`, `format_comparison_metadata`, `format_comparison_summary`, `format_comparison_top_diffs`). This decomposition avoids the long-function antipattern that appeared in earlier pipeline code.
- Attributes (`attr(diffs, "timestamp_a")` and `attr(diffs, "timestamp_b")`) are used to carry timestamps through the comparison pipeline without widening the struct interface -- a deliberate tradeoff (attributes survive `saveRDS` but are lost in JSON).

---

## Architectural Decisions

### Decision: Checkpoint writing only in the sequential artifact-writing loop, not in parallel workers

- **Chosen**: Write checkpoint after each artifact write in the sequential `lapply` loop (`R/train.r` lines 108-115), and after each per-plant result save in the sequential post-processing loop (`R/predict.r` lines 101-112).
- **Rejected**: Writing checkpoints inside `future_lapply` workers.
- **Rationale**: Concurrent checkpoint writes from parallel workers would require filesystem locking or atomic operations. By restricting checkpoint updates to the sequential phase, the implementation is safe with zero additional complexity.

### Decision: Resume is opt-in via explicit parameter, not auto-detected

- **Chosen**: `train_main(..., resume = FALSE)` and `predict_main(..., resume = FALSE)` default to clean starts. Resume requires `resume = TRUE` at call site (`R/train.r` line 39, `R/predict.r` line 37).
- **Rejected**: Auto-detecting a checkpoint file and always resuming if one exists.
- **Rationale**: Stale checkpoints from interrupted debugging sessions would silently corrupt production runs. The operator must explicitly signal intent to resume.

### Decision: predict resume saves per-plant intermediate results as RDS, not parquet

- **Chosen**: `write_plant_result()` saves `list(com_cortes = <data.table>, sem_cortes = <data.table>)` as RDS to `plant-result-{id_usina}.rds` in `args$output` (`R/provenance.r` line 319).
- **Rejected**: JSON or Parquet for intermediate plant results.
- **Rationale**: The per-plant result is a named list of two data.tables, not a single flat table. RDS serializes this structure exactly. Parquet requires a flat schema; JSON serialization of data.tables is non-trivial. RDS avoids any format impedance mismatch.

### Decision: metadata_diff uses R attributes to carry timestamps, not list widening

- **Chosen**: `attr(diffs, "timestamp_a")` and `attr(diffs, "timestamp_b")` in `compare_metadata()` in `R/model-comparison.r` (lines 188-189).
- **Rejected**: Adding `timestamp_a`/`timestamp_b` as named elements of the diffs list (confusing diff entries with report metadata).
- **Rationale**: Timestamps are not differences -- they are report context. Using attributes keeps the iteration loop clean (`for (d in md)`) without needing to filter non-diff entries.

### Decision: validate_artifact splits validation into small private helpers

- **Chosen**: `check_artifact_id_usina()`, `check_artifact_parametros()`, `check_artifact_metadata()` in `R/artifact.r` (lines 143-175) are separate, named functions.
- **Rejected**: Inline validation blocks inside `validate_artifact()`.
- **Rationale**: Each check becomes independently testable and the main function reads as a clean pipeline of concerns. This pattern matches what was established for validation in Epic 02 with `validate_input()` in `R/validation.r`.

---

## Files and Structures Created

- `/home/rogerio/git/mh-pfv/R/artifact.r` -- new file: `build_artifact_metadata`, `normalize_config_for_hash`, `get_config_hash_keys`, `build_model_artifact`, `validate_artifact`, and three private check helpers.
- `/home/rogerio/git/mh-pfv/R/provenance.r` -- new file: `generate_run_id`, `create_provenance`, `update_plant_status`, `finalize_provenance`, `write_provenance`, `format_provenance_timestamps`, `write_checkpoint`, `read_checkpoint`, `get_pending_plants`, `write_plant_result`, `read_plant_result`, `cleanup_checkpoint`.
- `/home/rogerio/git/mh-pfv/R/model-comparison.r` -- new file: `compare_artifacts`, `compare_artifact_files`, `format_comparison`, `compare_multiple_artifacts`, and 7 private helpers.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-artifact.r` -- unit tests for artifact functions; tests `normalize_config_for_hash` as an internal function.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-provenance.r` -- unit tests for all provenance and checkpoint functions; internal functions accessed via `mhpfv:::` triple-colon.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-model-comparison.r` -- unit tests for all comparison functions.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-pipeline-resume.r` -- integration tests for resume behavior on actual test data.

---

## Conventions Adopted

### Internal vs Exported Functions

- Functions intended for operator use are exported: `build_artifact_metadata`, `build_model_artifact`, `validate_artifact`, `generate_run_id`, `create_provenance`, `update_plant_status`, `finalize_provenance`, `write_provenance`, `write_checkpoint`, `read_checkpoint`, `get_pending_plants`, `compare_artifacts`, `compare_artifact_files`, `format_comparison`, `compare_multiple_artifacts`.
- Internal helpers (`write_plant_result`, `read_plant_result`, `cleanup_checkpoint`, `format_provenance_timestamps`, `normalize_config_for_hash`) are not exported. Tests access them via `mhpfv:::` to verify correctness without exposing them as API surface.
- This export boundary avoids polluting the namespace with I/O utilities that could change without notice.

### Checkpoint and Plant-result File Naming

- Checkpoints: `checkpoint-{run_id}.json` in the artifact or output directory.
- Plant results: `plant-result-{id_usina}.rds` in the output directory.
- Provenance: `provenance-{run_id}.json` in the artifact or output directory.
- All three file types are cleanly distinguishable by prefix, enabling selective cleanup with `list.files(..., pattern = "^checkpoint-.*\\.json$")` without ambiguity.

### Test Access to Internal Functions

- Tests for provenance and checkpoint internals use `mhpfv:::write_checkpoint(...)`, `mhpfv:::read_checkpoint(...)`, etc. in `test-provenance.r` (line 319, 379, etc.). This is consistent with the `mhpfv:::get_model_artifact()` pattern already in `R/predict.r` -- acceptable for test-only access to implementation details.

### Legacy artifact handling convention

- Old-format artifacts (without `metadata`) are accepted everywhere by testing for `"metadata" %in% names(artifact)`. No format migration is triggered; the warn-and-continue pattern is uniform across `validate_artifact()` in `R/artifact.r` and `has_metadata()` helper used in `R/model-comparison.r`.

---

## Surprises and Deviations

### Deviation: validate_artifact refactored to use private check helpers, not inline blocks

- **Expected** (from ticket): A single flat function body collecting errors in a `character(0L)` vector (matching the spec in the implementation guide of E04-T001).
- **Actual**: The validation logic was split into three private functions (`check_artifact_id_usina`, `check_artifact_parametros`, `check_artifact_metadata`) called from the main function body (`R/artifact.r` lines 127-138). The error-collection invariant is preserved but the structure is more modular than specified.
- **Location**: `/home/rogerio/git/mh-pfv/R/artifact.r` lines 143-175.

### Deviation: compare_artifacts avoids double-computation of coefficient_diff

- **Expected** (from ticket implementation guide): `coefficient_diff` computed twice -- once for the `coefficient_diff` field and once for `summary`.
- **Actual**: `coeff_dt` is computed once and passed to both `compare_coefficients` result and `summarize_coefficient_diff(coeff_dt)` (`R/model-comparison.r` lines 26-36). A minor correctness improvement that eliminates redundant computation.

### Deviation: provenance <<- comment added explicitly

- **Expected**: Silent implementation detail.
- **Actual**: A comment `# <<- necessario para atualizar provenance no escopo da funcao pai` is placed on the line before each `<<-` usage in both `R/train.r` (line 110) and `R/predict.r` (line 107). This is a documentation practice addition the ticket did not specify but improves maintainability for R developers unfamiliar with closure-based state mutation.

### Deviation: cleanup_checkpoint not exported

- **Expected** (from ticket): The ticket listed `cleanup_checkpoint` among the functions to export.
- **Actual**: `cleanup_checkpoint` is not in NAMESPACE -- it is an internal function accessible only via `mhpfv:::`. This is a tighter API surface; the cleanup function is an implementation detail called exclusively from `train_main` and `predict_main` and has no use case as a standalone operator tool.
- **Impact**: Tests call it as `mhpfv:::cleanup_checkpoint()`. If future epics need to expose cleanup as a CLI command, this will require adding a NAMESPACE export.

### Surprise: read_checkpoint test for config hash mismatch does not expect a warning

- **Expected** (from ticket): `read_checkpoint` with mismatched config hash should log a warning.
- **Actual**: The test at `test-provenance.r` line 425 uses `expect_no_warning(f(tmp, cfg_b))`, meaning the warning is emitted via `lgr` (not `base::warning()`). Since `lgr` messages do not propagate as R conditions, `expect_warning()` would not capture them. The test correctly confirms no R-level warning is raised, with the lgr logging handled separately.

---

## Recommendations for Future Epics

### For Epic 05 (Infrastructure Hardening)

- The `resume = TRUE` parameter exists on `train_main` and `predict_main` but is not wired to the CLI parser (`R/cli.r`). Epic 05 should add a `--resume` flag in `R/parser.r` alongside `--parallel`. See `/home/rogerio/git/mh-pfv/R/cli.r` for the dispatch pattern and `R/train.r` line 39 for the parameter signature.
- The `normalize_config_for_hash()` key list in `R/artifact.r` (line 58-64) is hardcoded. If Epic 05 changes the config schema (e.g., adds new configuration keys that should affect model identity), this list must be updated. Consider adding a test that verifies the key list matches the schema in `config-file.r`.
- The Docker build that resolves `ARROW_WITH_ZSTD=ON` (deferred from Epic 03) would also unblock the `predict_main` integration tests in `test-pipeline-resume.r`, which depend on reading Parquet from the test dataset. The resume integration tests already use `skip_if_not(dir.exists(test_path("data")))` as the guard.
- `cleanup_checkpoint` is internal. If a future CLI command `mhpfv cleanup` is added, promote it to exported in NAMESPACE.

### For Epic 06 (Observability and Monitoring)

- The `provenance-{run_id}.json` files written by `write_provenance()` in `R/provenance.r` are the natural feed for a pipeline health report. Epic 06 can read these files from a designated provenance directory, aggregate `duration_seconds`, `n_plants`, `status`, and `plant_status` counts, and produce a health summary without any schema changes.
- The `lgr::get_logger("mhpfv")` call pattern is already used consistently for all provenance and checkpoint log messages. Epic 06 structured logging work should configure log appenders on this same logger rather than introducing a new logger name.
- `generate_run_id()` in `R/provenance.r` (line 17) already includes mode, date, time, and a 4-hex suffix. If Epic 06 needs correlation IDs for distributed tracing, the run ID is already structured for that purpose.
- The `plant_status` field in provenance JSON maps plant IDs to `"completed"`, `"failed"`, or `"skipped"`. Epic 06 pipeline metrics could aggregate failure rates by plant ID across multiple provenance files to identify chronically failing plants.

### General Recommendations

- The `data.table::data.table()` with `unname()` calls in `compare_coefficients()` (`R/model-comparison.r` lines 212-218) prevents named vectors from creating unexpected column names. This pattern -- `unname()` on named vectors before passing to `data.table()` constructor -- should be documented as a codebase convention.
- The `on.exit(..., add = TRUE)` registration ordering (provenance first, parallel cleanup second) is critical and non-obvious. A comment should be added to both `train_main` and `predict_main` at the `on.exit` registration site explaining the LIFO evaluation order and why provenance must be registered first.
- The `withr::local_tempdir()` pattern is used correctly throughout the new integration tests. All future file-system-touching tests should follow this pattern -- never use `tempdir()` directly, as it is not cleaned up between test runs.

---

## Technical Debt Introduced

- `cleanup_checkpoint` is internal but the ticket spec implied it would be exported. If a future operator needs to manually clean up a stale checkpoint (e.g., after a crashed run during debugging), they must use `mhpfv:::cleanup_checkpoint(dir)`. This should be re-evaluated when the CLI gains a `--resume` flag.
- The `attr(diffs, "timestamp_a")` approach in `compare_metadata()` (`R/model-comparison.r` lines 188-189) is fragile: attributes are silently dropped when the list is serialized to JSON or passed through some list manipulation functions. If a future ticket needs to serialize comparison results, this must be changed to named list elements.
- `read_checkpoint()` selects the most recent checkpoint by `file.mtime()` (`R/provenance.r` line 258). File modification times are filesystem-dependent and can be unreliable on shared network filesystems or when files are copied between systems. A more robust approach would parse the timestamp embedded in the run ID (`checkpoint-{run_id}.json`) for ordering.
- Plant-result intermediate files (`plant-result-{id_usina}.rds`) are written to `args$output` only when `resume = TRUE` (`R/predict.r` line 102). In a non-resume run they are never written. If a non-resume run crashes after partial processing, resuming is not possible without reprocessing from scratch. To make all predict runs resumable by default, plant-result writing could be made unconditional at a small I/O overhead cost.
