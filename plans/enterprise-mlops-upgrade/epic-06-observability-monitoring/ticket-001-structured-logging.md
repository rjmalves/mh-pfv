# E06-T001 Enhance Structured Logging with Run Context

## Context

### Background

The mhpfv package uses `lgr` as its logging library. The logger is initialized in `R/logging.r::logger_setup()`, which configures the root logger with a `LayoutFormat` and a threshold from the `LOG_LEVEL` environment variable. A package-level `lg` binding is created by `.onLoad()` in `R/zzz.r` and accessed via `get_pkg_logger()`. Throughout the codebase, modules obtain their logger via `lgr::get_logger("mhpfv")` (e.g., in `R/provenance.r`, `R/cli.r`, `R/parallel.r`, `R/artifact.r`).

Currently, log messages are plain text with `sprintf`-style formatting. There is no run context (run ID, pipeline mode, plant ID, pipeline stage) attached to log entries. This makes it difficult to correlate log lines to specific runs or plants in production environments where multiple runs might produce interleaved logs, or where operators need to trace an issue back to a specific pipeline execution.

The learnings from Epic 04 established provenance infrastructure that generates a `run_id` at the start of each pipeline execution via `create_provenance()`. This `run_id` is available in both `train_main()` and `predict_main()` and is a natural piece of context to inject into every log message.

### Relation to Epic

This ticket is the foundation of Epic 06 (Observability and Monitoring). It enhances the logging infrastructure so that all subsequent tickets (E06-T002 metrics, E06-T003 health report) can emit structured, context-aware log messages. The structured logging also benefits operators who need to filter and aggregate logs from production pipeline runs.

### Current State

**`R/logging.r`** -- Logger setup and accessor:

```r
logger_setup <- function() {
    lg <- get_logger()
    lg$set_threshold(Sys.getenv("LOG_LEVEL", unset = "info"))
    layout <- LayoutFormat$new(timestamp_fmt = "%Y-%m-%d %H:%M:%S")
    lg$appenders$console$set_layout(layout)
    lg
}

get_pkg_logger <- function() {
    get("lg", envir = asNamespace("mhpfv"))
}
```

**`R/zzz.r`** -- Logger initialization on package load:

```r
.onLoad <- function(libname, pkgname) {
    lg <- logger_setup()
    assign("lg", lg, asNamespace("mhpfv"))
}
```

**`R/cli.r`** -- Pipeline entry point (no context logging):

```r
cli_main <- function(datadir = "./data", parallel = FALSE, resume = FALSE,
    workers = NULL) {
    lg <- get_pkg_logger()
    if (!isTRUE(parallel)) {
        parallel <- read_env_flag("MHPFV_PARALLEL", FALSE)
    }
    # ... parameter resolution, then dispatches to train_main or predict_main
}
```

**`R/provenance.r`** -- run_id is created but never logged at startup:

```r
create_provenance <- function(config, mode, parallel = FALSE) {
    run_id <- generate_run_id(mode)
    # ... builds provenance record, returns list with run_id
}
```

**`R/train.r`** -- provenance created at top of pipeline:

```r
train_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE, resume = FALSE) {
    provenance <- create_provenance(args, "train", parallel)
    # ... no structured log context set
}
```

**`R/predict.r`** -- same pattern:

```r
predict_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE, resume = FALSE) {
    provenance <- create_provenance(args, "predict", parallel)
    # ... no structured log context set
}
```

Log messages are scattered throughout the codebase with no structured context fields. The `lgr` library natively supports structured fields via `$set_fields()` on the logger, and `LayoutJson` for JSON-formatted output.

## Specification

### Requirements

1. **Add `set_log_context()` helper** in `R/logging.r` that sets structured fields (`run_id`, `mode`, `stage`) on the `mhpfv` logger via `lgr`'s `$set_fields()` mechanism. These fields will automatically appear in every subsequent log message from that logger.

2. **Add `clear_log_context()` helper** in `R/logging.r` that removes all custom context fields from the logger (for cleanup and testing).

3. **Add `configure_json_logging()` helper** in `R/logging.r` that, when the `MHPFV_LOG_FORMAT` environment variable is set to `"json"`, replaces the default console appender layout with `lgr::LayoutJson`. This is opt-in; the default remains the human-readable `LayoutFormat`.

4. **Set run context at pipeline start** in `train_main()` and `predict_main()`, immediately after `create_provenance()` returns. Set fields: `run_id`, `mode`. Clean up context on exit.

5. **Log resolved runtime parameters at startup** in `cli_main()`, after parameter resolution but before dispatching to train/predict. Log `parallel`, `resume`, `workers` values and the `MHPFV_PARALLEL`, `MHPFV_RESUME`, `MHPFV_WORKERS` environment variable raw values (as recommended by Epic 05 learnings).

6. **Add per-plant progress logging** in the post-processing `lapply` blocks of `train_main()` and `predict_main()`. After each plant completes, log a progress message including plant ID and completion fraction (e.g., "Usina BAUFI1 concluida (1/5)").

### Inputs/Props

| Function                               | Parameters                                                      | Description                                                            |
| -------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `set_log_context(run_id, mode, stage)` | `run_id` character, `mode` character, `stage` character or NULL | Sets structured fields on the mhpfv logger                             |
| `clear_log_context()`                  | none                                                            | Removes `run_id`, `mode`, `stage` fields from logger                   |
| `configure_json_logging()`             | none                                                            | Checks `MHPFV_LOG_FORMAT` env var; if `"json"`, switches to LayoutJson |

### Outputs/Behavior

- When `MHPFV_LOG_FORMAT` is unset or set to any value other than `"json"`, log output remains human-readable text with timestamp (current behavior). The context fields (`run_id`, `mode`, `stage`) are included in the format string via a custom `LayoutFormat` pattern that appends them.
- When `MHPFV_LOG_FORMAT=json`, each log line is a JSON object containing `timestamp`, `level`, `msg`, and any custom fields (`run_id`, `mode`, `stage`).
- After `train_main()` calls `create_provenance()`, all subsequent log messages from the `mhpfv` logger include `run_id` and `mode` fields.
- `cli_main()` emits an INFO-level log message showing the resolved values of `parallel`, `resume`, and `workers`, plus the raw environment variable values for auditability.
- After each plant completes processing, an INFO-level progress message is logged showing plant ID and progress fraction.

### Error Handling

- `set_log_context()` silently ignores `NULL` values for optional fields (e.g., `stage = NULL` means no stage field is set).
- `configure_json_logging()` uses `tryCatch` so that a failure to configure JSON output (e.g., missing `LayoutJson` class) logs a warning and falls back to the default layout. This ensures the pipeline never crashes due to logging configuration.
- If `clear_log_context()` is called when no context is set, it is a no-op (no error).

## Acceptance Criteria

- [ ] Given `train_main()` is called, when provenance is created, then all subsequent log messages from `lgr::get_logger("mhpfv")` include `run_id` and `mode` fields
- [ ] Given `predict_main()` is called, when provenance is created, then all subsequent log messages include `run_id` and `mode` fields
- [ ] Given `MHPFV_LOG_FORMAT=json` in the environment, when `logger_setup()` runs, then log output is JSON-formatted with structured fields
- [ ] Given `MHPFV_LOG_FORMAT` is unset, when `logger_setup()` runs, then log output remains human-readable text (backward compatible)
- [ ] Given `cli_main()` is called with `MHPFV_PARALLEL=true` and `MHPFV_WORKERS=4`, when parameter resolution completes, then an INFO log message shows `parallel=TRUE`, `resume=FALSE`, `workers=4` and the raw env var values
- [ ] Given `train_main()` processes 3 plants, when each plant completes, then a log message like "Usina USI1 concluida (1/3)" is emitted
- [ ] Given `set_log_context(run_id = "test-123", mode = "train", stage = NULL)`, when called, then `run_id` and `mode` are set on the logger but `stage` is not
- [ ] Given `clear_log_context()` is called, when subsequent log messages are emitted, then no `run_id`, `mode`, or `stage` fields are present
- [ ] Given `devtools::check()` is run, when checks complete, then no new NOTEs, WARNINGs, or ERRORs are introduced

## Implementation Guide

### Suggested Approach

1. **Enhance `R/logging.r`** with context management functions. The `lgr` package supports custom fields on loggers via `$set_fields()` (adds fields to all events from this logger) and `$remove_fields()`:

   ```r
   #' Define Contexto Estruturado no Logger
   #'
   #' Adiciona campos de contexto (run_id, mode, stage) ao logger do pacote.
   #' Esses campos aparecem automaticamente em todas as mensagens subsequentes.
   #'
   #' @param run_id character escalar, identificador da execucao
   #' @param mode character escalar, modo do pipeline ("train" ou "predict")
   #' @param stage character escalar ou NULL, estagio atual do pipeline
   #'
   #' @return invisible(NULL)
   set_log_context <- function(run_id, mode, stage = NULL) {
       lg <- lgr::get_logger("mhpfv")
       fields <- list(run_id = run_id, mode = mode)
       if (!is.null(stage)) fields$stage <- stage
       lg$set_fields(fields)
       invisible(NULL)
   }

   #' Remove Contexto Estruturado do Logger
   #'
   #' Remove os campos run_id, mode e stage do logger do pacote.
   #'
   #' @return invisible(NULL)
   clear_log_context <- function() {
       lg <- lgr::get_logger("mhpfv")
       lg$set_fields(NULL)
       invisible(NULL)
   }
   ```

2. **Add JSON logging configuration** in `R/logging.r`. Enhance `logger_setup()` to call `configure_json_logging()` after the standard setup:

   ```r
   configure_json_logging <- function(lg) {
       fmt <- Sys.getenv("MHPFV_LOG_FORMAT", unset = "")
       if (tolower(trimws(fmt)) != "json") return(invisible(NULL))

       tryCatch({
           lg$appenders$console$set_layout(lgr::LayoutJson$new())
       }, error = function(e) {
           # Fallback: keep existing layout if LayoutJson fails
           warning(
               "Falha ao configurar log JSON: ", conditionMessage(e),
               call. = FALSE
           )
       })
       invisible(NULL)
   }
   ```

   Update `logger_setup()` to call it:

   ```r
   logger_setup <- function() {
       lg <- get_logger()
       lg$set_threshold(Sys.getenv("LOG_LEVEL", unset = "info"))
       layout <- LayoutFormat$new(timestamp_fmt = "%Y-%m-%d %H:%M:%S")
       lg$appenders$console$set_layout(layout)
       configure_json_logging(lg)
       lg
   }
   ```

3. **Set context in `train_main()` and `predict_main()`** immediately after `create_provenance()`:

   ```r
   # In train_main(), after line: provenance <- create_provenance(args, "train", parallel)
   set_log_context(provenance$run_id, "train")
   on.exit(clear_log_context(), add = TRUE)
   ```

   Same pattern in `predict_main()` with `"predict"`.

4. **Log runtime parameters in `cli_main()`** after the parameter resolution block (after the `workers` warning check, before `conn <- conectamock_pfv(datadir)`):

   ```r
   lg$info(
       paste0(
           "Parametros resolvidos: parallel=%s, resume=%s, workers=%s | ",
           "ENV: MHPFV_PARALLEL='%s', MHPFV_RESUME='%s', MHPFV_WORKERS='%s'"
       ),
       parallel, resume,
       if (is.null(workers)) "auto" else workers,
       Sys.getenv("MHPFV_PARALLEL", unset = ""),
       Sys.getenv("MHPFV_RESUME", unset = ""),
       Sys.getenv("MHPFV_WORKERS", unset = "")
   )
   ```

5. **Add per-plant progress logging** in the post-processing `lapply` blocks. In `train_main()`, modify the sequential `lapply` that writes artifacts (lines 108-115):

   ```r
   n_total <- length(v_usinas)
   lapply(seq_along(v_usinas), function(i) {
       write_model_artifact(models[[i]], v_usinas[i], args$artifact)
       # <<- necessario para atualizar provenance no escopo da funcao pai
       provenance <<- update_plant_status(
           provenance, v_usinas[i], "completed"
       )
       if (resume) write_checkpoint(provenance, args$artifact)
       lg$info("Usina %s concluida (%d/%d)", v_usinas[i], i, n_total)
   })
   ```

   In `predict_main()`, similarly modify the for-loop that processes completed plants (lines 101-112):

   ```r
   n_total <- length(v_usinas_pending)
   for (i in seq_along(v_usinas_pending)) {
       if (resume) {
           write_plant_result(
               resultados_new[[i]], v_usinas_pending[i], args$output
           )
       }
       # <<- necessario para atualizar provenance no escopo da funcao pai
       provenance <<- update_plant_status(
           provenance, v_usinas_pending[i], "completed"
       )
       if (resume) write_checkpoint(provenance, args$output)
       lg$info("Usina %s concluida (%d/%d)", v_usinas_pending[i], i, n_total)
   }
   ```

   Note: `lg` must be obtained at the top of these functions. In `train_main()`, add `lg <- lgr::get_logger("mhpfv")` after `set_log_context()`. In `predict_main()`, same.

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/logging.r` -- Add `set_log_context()`, `clear_log_context()`, `configure_json_logging()`, update `logger_setup()`
- `/home/rogerio/git/mh-pfv/R/cli.r` -- Add runtime parameter logging after resolution
- `/home/rogerio/git/mh-pfv/R/train.r` -- Set log context after provenance creation, add progress logging
- `/home/rogerio/git/mh-pfv/R/predict.r` -- Set log context after provenance creation, add progress logging
- `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r` -- New test file for logging functions

### Patterns to Follow

- Use `lgr::get_logger("mhpfv")` consistently (not a new logger name) -- established across all modules
- Non-exported helper functions documented with roxygen2 docblocks without `@export` tag -- consistent with `validate_workers()` in `R/parallel.r`, `format_provenance_timestamps()` in `R/provenance.r`
- Portuguese for all log messages -- consistent with entire codebase
- `on.exit(..., add = TRUE)` for cleanup -- consistent with provenance and parallel plan cleanup in `train_main()` and `predict_main()`
- `tryCatch` wrapping for optional features that must not crash the pipeline -- consistent with `write_provenance()` and `write_checkpoint()`
- `withr::local_envvar()` for environment variable tests -- consistent with `test-cli.r`

### Pitfalls to Avoid

- **lgr log messages do NOT propagate as R conditions** -- `expect_warning()` and `expect_message()` will NOT catch lgr output. To test that logging works, either: (a) test that `set_log_context()` actually sets fields on the logger by inspecting `lgr::get_logger("mhpfv")$fields`, or (b) add a temporary `AppenderBuffer` and inspect captured events. Do NOT use `expect_warning()` for log verification.
- **`lgr::LayoutJson` class name** -- verify the exact class name. In lgr >= 0.4.0, it is `LayoutJson`. The package already depends on `lgr (>= 0.4.4)`, so this is safe.
- **Parallel workers get their own logger instances** -- `set_log_context()` on the main process logger does not propagate to future workers. This is acceptable because parallel workers do not emit structured log messages through the main logger. Progress logging happens in the sequential post-processing step, not inside workers.
- **Do NOT modify the `LOG_LEVEL` behavior** -- the existing `LOG_LEVEL` env var must continue to work exactly as before. The new `MHPFV_LOG_FORMAT` env var is additive.
- **Do NOT add `MHPFV_LOG_FORMAT` to DESCRIPTION Imports** -- `lgr` is already imported; `LayoutJson` is part of `lgr`.

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-logging.r`:

1. **`set_log_context()` tests**:
   - Sets `run_id` and `mode` fields on the logger; verify via `lgr::get_logger("mhpfv")$fields`
   - Sets `stage` when provided; verify it appears in fields
   - Does not set `stage` when `NULL`; verify it is absent from fields
   - Cleanup: always call `clear_log_context()` in `withr::defer()` to avoid leaking state

2. **`clear_log_context()` tests**:
   - After `set_log_context()`, calling `clear_log_context()` removes all custom fields
   - Calling `clear_log_context()` when no context is set does not error

3. **`configure_json_logging()` tests**:
   - With `MHPFV_LOG_FORMAT=json`, verify the logger's console appender layout is `LayoutJson` (use `withr::local_envvar(MHPFV_LOG_FORMAT = "json")`)
   - With `MHPFV_LOG_FORMAT` unset, verify layout remains `LayoutFormat`
   - Cleanup: restore original logger state after each test

4. **`logger_setup()` tests**:
   - Returns a logger object
   - Respects `LOG_LEVEL` environment variable

### Integration Tests

- `devtools::check()` passes without new issues
- `devtools::test()` passes all existing tests (no regressions from log context changes)

## Dependencies

- **Blocked By**: E04-T002 (run provenance -- completed)
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
