# E06-T002 Add Pipeline Metrics Collection

## Context

### Background

The mhpfv pipeline processes solar photovoltaic generation data through train and predict pipelines. The provenance system (Epic 04) already captures high-level execution metadata -- run ID, start/end times, duration, plant count, and per-plant status -- in `provenance-{run_id}.json` files. However, there are no fine-grained metrics about the pipeline's internal behavior: per-plant timing, data volumes processed, NA rates in input data, or model quality indicators from training.

These metrics are essential for ONS operators to understand pipeline health beyond simple pass/fail status. For example, a pipeline run might "succeed" but produce low-quality results because 80% of input data was NA, or because a specific plant took 10x longer than expected (indicating data anomalies). Without metrics, operators have no visibility into these internal quality signals.

The learnings from earlier epics established that provenance records already contain `duration_seconds`, `n_plants`, `status`, and `plant_status` fields. This ticket adds a complementary metrics system that captures finer-grained data and writes it alongside provenance as `metrics-{run_id}.json`.

### Relation to Epic

This ticket provides the metrics collection infrastructure that E06-T003 (Health Report) will aggregate into a comprehensive health summary. The metrics file provides raw, per-plant detail; the health report provides aggregated indicators suitable for monitoring dashboards. E06-T001 (Structured Logging) provides context-aware logging that metrics collection will use to announce what it captures.

### Current State

**`R/provenance.r`** -- Provenance record structure (already captures some metrics-adjacent data):

```r
create_provenance <- function(config, mode, parallel = FALSE) {
    run_id <- generate_run_id(mode)
    plant_ids <- config$ids_usinas
    plant_status <- as.list(rep("pending", length(plant_ids)))
    names(plant_status) <- plant_ids
    list(
        run_id = run_id,
        mode = mode,
        package_version = ...,
        r_version = ...,
        start_time = Sys.time(),
        end_time = NULL,
        duration_seconds = NULL,
        config_hash = ...,
        n_plants = length(plant_ids),
        plant_ids = plant_ids,
        plant_status = plant_status,
        parallel = parallel,
        status = "running"
    )
}
```

**`R/train.r`** -- Plant processing with no per-plant timing:

```r
# Parallel or sequential processing of plants
models <- lapply(v_usinas, ajustar_usina, ...)

# Post-processing: write artifacts, update provenance
lapply(seq_along(v_usinas), function(i) {
    write_model_artifact(models[[i]], v_usinas[i], args$artifact)
    provenance <<- update_plant_status(provenance, v_usinas[i], "completed")
    if (resume) write_checkpoint(provenance, args$artifact)
})
```

**`R/predict.r`** -- Same pattern, no per-plant timing or data volume tracking:

```r
resultados_new <- do.call(lapply, apply_args)

for (i in seq_along(v_usinas_pending)) {
    if (resume) write_plant_result(resultados_new[[i]], v_usinas_pending[i], args$output)
    provenance <<- update_plant_status(provenance, v_usinas_pending[i], "completed")
    if (resume) write_checkpoint(provenance, args$output)
}
```

**`R/artifact.r`** -- Model metadata already captures some quality indicators:

```r
build_artifact_metadata <- function(strategy, model, config) {
    meta <- model_metadata(strategy, model)
    # meta contains: type, n_slots, n_valid_slots, mean_coefficient, timestamp
    meta$package_version <- as.character(utils::packageVersion("mhpfv"))
    meta$config_hash <- digest::digest(normalize_config_for_hash(config), algo = "sha256")
    meta
}
```

No metrics file is produced today. Only `provenance-{run_id}.json` is written.

## Specification

### Requirements

1. **Create `R/metrics.r`** with a metrics collection system that:
   - Creates a metrics record at pipeline start via `create_metrics(run_id, mode)`
   - Records per-plant timing via `record_plant_timing(metrics, id_usina, duration_secs)`
   - Records per-plant data volume via `record_plant_data_volume(metrics, id_usina, n_rows, n_na, n_total)`
   - Records model quality summary for train mode via `record_model_quality(metrics, id_usina, metadata)` (extracts `n_slots`, `n_valid_slots`, `mean_coefficient` from artifact metadata)
   - Finalizes metrics with pipeline-level aggregates via `finalize_metrics(metrics)`
   - Writes metrics to `metrics-{run_id}.json` via `write_metrics(metrics, output_dir)`

2. **Instrument `train_main()`** to:
   - Create a metrics record after provenance
   - Time each plant's processing (wrap `ajustar_usina` calls with `proc.time()` delta)
   - Record model quality from artifact metadata after each plant
   - Finalize and write metrics alongside provenance

3. **Instrument `predict_main()`** to:
   - Create a metrics record after provenance
   - Time each plant's processing
   - Record data volume (row count from the predict result data.tables)
   - Finalize and write metrics alongside provenance

4. **Metrics file format** -- `metrics-{run_id}.json` with this structure:

   ```json
   {
     "run_id": "train-20260222-143052-a1b2",
     "mode": "train",
     "created_at": "2026-02-22T14:31:15Z",
     "pipeline": {
       "total_duration_seconds": 42.5,
       "n_plants": 5,
       "n_plants_completed": 5,
       "mean_plant_duration_seconds": 8.5,
       "max_plant_duration_seconds": 15.2,
       "min_plant_duration_seconds": 3.1
     },
     "plants": {
       "BAUFI1": {
         "duration_seconds": 8.5,
         "data_volume": { "n_rows": 1440, "n_na": 120, "na_rate": 0.0833 },
         "model_quality": {
           "n_slots": 28,
           "n_valid_slots": 26,
           "mean_coefficient": 0.031
         }
       }
     }
   }
   ```

### Inputs/Props

| Function                                                             | Parameters                                                    | Description                        |
| -------------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------- |
| `create_metrics(run_id, mode)`                                       | `run_id` character, `mode` character                          | Creates empty metrics record       |
| `record_plant_timing(metrics, id_usina, duration_secs)`              | `metrics` list, `id_usina` character, `duration_secs` numeric | Records timing for one plant       |
| `record_plant_data_volume(metrics, id_usina, n_rows, n_na, n_total)` | all scalars                                                   | Records data volume for one plant  |
| `record_model_quality(metrics, id_usina, metadata)`                  | `metadata` list from artifact                                 | Records model quality indicators   |
| `finalize_metrics(metrics)`                                          | `metrics` list                                                | Computes pipeline-level aggregates |
| `write_metrics(metrics, output_dir)`                                 | `metrics` list, `output_dir` character                        | Writes JSON file                   |

### Outputs/Behavior

- `create_metrics()` returns a list with `run_id`, `mode`, `created_at = NULL`, `pipeline = list()`, `plants = list()`.
- `record_plant_timing()` adds `duration_seconds` to the plant's entry in `metrics$plants`. Returns updated metrics (copy-on-modify, same pattern as `update_plant_status()`).
- `record_plant_data_volume()` adds `data_volume` sub-list to the plant's entry. Returns updated metrics.
- `record_model_quality()` adds `model_quality` sub-list to the plant's entry. Returns updated metrics. Only called in train mode.
- `finalize_metrics()` computes `pipeline` aggregates from per-plant data: `total_duration_seconds` (from provenance), `n_plants`, `n_plants_completed`, `mean_plant_duration_seconds`, `max_plant_duration_seconds`, `min_plant_duration_seconds`. Sets `created_at` to current UTC timestamp. Returns updated metrics.
- `write_metrics()` serializes to JSON and writes `metrics-{run_id}.json`. Follows the same error-handling pattern as `write_provenance()` -- wrapped in `tryCatch`, never crashes the pipeline.

### Error Handling

- All `record_*` functions validate inputs with `stopifnot()` (same pattern as `update_plant_status()`).
- `write_metrics()` is wrapped in `tryCatch` -- I/O failures log a warning via `lgr::get_logger("mhpfv")` and do not crash the pipeline. This is the same pattern as `write_provenance()`.
- If a plant fails during processing, its metrics entry will be incomplete (no timing, no data volume). This is acceptable -- the provenance record captures the failure status.
- `finalize_metrics()` handles edge cases: zero plants completed (all aggregates are `NA_real_`).

## Acceptance Criteria

- [ ] Given a `train_main()` run with 2 plants, when the run completes, then a `metrics-{run_id}.json` file exists alongside `provenance-{run_id}.json` in the artifact directory
- [ ] Given the metrics file from a train run, when parsed, then it contains per-plant entries with `duration_seconds` and `model_quality` fields
- [ ] Given a `predict_main()` run with 2 plants, when the run completes, then a `metrics-{run_id}.json` file exists in the output directory
- [ ] Given the metrics file from a predict run, when parsed, then it contains per-plant entries with `duration_seconds` and `data_volume` fields
- [ ] Given the metrics file, when the `pipeline` section is inspected, then `mean_plant_duration_seconds`, `max_plant_duration_seconds`, and `min_plant_duration_seconds` are computed correctly from per-plant timings
- [ ] Given `write_metrics()` is called with an invalid output directory, when it fails, then no error propagates (only a log warning)
- [ ] Given `create_metrics("test-id", "train")`, when called, then it returns a list with `run_id`, `mode`, `created_at = NULL`, `pipeline = list()`, `plants = list()`
- [ ] Given `record_plant_timing()` called with a non-numeric duration, when called, then it raises an error via `stopifnot`
- [ ] Given `devtools::check()` is run, when checks complete, then no new NOTEs, WARNINGs, or ERRORs are introduced

## Implementation Guide

### Suggested Approach

1. **Create `R/metrics.r`** with the metrics collection functions:

   ```r
   #' Cria Registro de Metricas de Execucao
   #'
   #' Inicializa a estrutura de metricas para coleta durante a execucao
   #' do pipeline. Metricas sao acumuladas por usina e agregadas na
   #' finalizacao.
   #'
   #' @param run_id character escalar, identificador da execucao
   #' @param mode character escalar, "train" ou "predict"
   #'
   #' @return lista com estrutura de metricas vazia
   create_metrics <- function(run_id, mode) {
       stopifnot(
           is.character(run_id), length(run_id) == 1L,
           is.character(mode), length(mode) == 1L
       )
       list(
           run_id = run_id,
           mode = mode,
           created_at = NULL,
           pipeline = list(),
           plants = list()
       )
   }

   #' Registra Tempo de Processamento de Uma Usina
   #'
   #' @param metrics lista de metricas criada por [create_metrics()]
   #' @param id_usina character escalar
   #' @param duration_secs numeric escalar, duracao em segundos
   #'
   #' @return lista de metricas atualizada
   record_plant_timing <- function(metrics, id_usina, duration_secs) {
       stopifnot(
           is.list(metrics),
           is.character(id_usina), length(id_usina) == 1L,
           is.numeric(duration_secs), length(duration_secs) == 1L
       )
       if (is.null(metrics$plants[[id_usina]])) {
           metrics$plants[[id_usina]] <- list()
       }
       metrics$plants[[id_usina]]$duration_seconds <- duration_secs
       metrics
   }

   #' Registra Volume de Dados Processados de Uma Usina
   #'
   #' @param metrics lista de metricas
   #' @param id_usina character escalar
   #' @param n_rows inteiro, total de linhas processadas
   #' @param n_na inteiro, numero de valores NA
   #' @param n_total inteiro, numero total de valores (pode diferir de n_rows
   #'   para dados com multiplas colunas de valor)
   #'
   #' @return lista de metricas atualizada
   record_plant_data_volume <- function(metrics, id_usina, n_rows, n_na,
       n_total) {
       stopifnot(
           is.list(metrics),
           is.character(id_usina), length(id_usina) == 1L,
           is.numeric(n_rows), length(n_rows) == 1L,
           is.numeric(n_na), length(n_na) == 1L,
           is.numeric(n_total), length(n_total) == 1L
       )
       if (is.null(metrics$plants[[id_usina]])) {
           metrics$plants[[id_usina]] <- list()
       }
       na_rate <- if (n_total > 0) n_na / n_total else NA_real_
       metrics$plants[[id_usina]]$data_volume <- list(
           n_rows = as.integer(n_rows),
           n_na = as.integer(n_na),
           na_rate = round(na_rate, 4L)
       )
       metrics
   }

   #' Registra Qualidade do Modelo Ajustado para Uma Usina
   #'
   #' Extrai indicadores de qualidade dos metadados do artefato de modelo.
   #' Chamada apenas no modo train.
   #'
   #' @param metrics lista de metricas
   #' @param id_usina character escalar
   #' @param metadata lista de metadados do artefato (retornada por
   #'   [build_artifact_metadata()])
   #'
   #' @return lista de metricas atualizada
   record_model_quality <- function(metrics, id_usina, metadata) {
       stopifnot(
           is.list(metrics),
           is.character(id_usina), length(id_usina) == 1L,
           is.list(metadata)
       )
       if (is.null(metrics$plants[[id_usina]])) {
           metrics$plants[[id_usina]] <- list()
       }
       metrics$plants[[id_usina]]$model_quality <- list(
           n_slots = metadata$n_slots,
           n_valid_slots = metadata$n_valid_slots,
           mean_coefficient = metadata$mean_coefficient
       )
       metrics
   }
   ```

2. **Add `finalize_metrics()` and `write_metrics()`**:

   ```r
   #' Finaliza Metricas com Agregados do Pipeline
   #'
   #' Computa estatisticas agregadas a partir das metricas por usina.
   #'
   #' @param metrics lista de metricas
   #'
   #' @return lista de metricas com campo pipeline preenchido
   finalize_metrics <- function(metrics) {
       stopifnot(is.list(metrics))

       durations <- vapply(
           metrics$plants,
           function(p) {
               if (!is.null(p$duration_seconds)) p$duration_seconds
               else NA_real_
           },
           numeric(1L)
       )
       valid_durations <- durations[!is.na(durations)]

       metrics$created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
       metrics$pipeline <- list(
           n_plants = length(metrics$plants),
           n_plants_completed = length(valid_durations),
           mean_plant_duration_seconds = if (length(valid_durations) > 0L)
               round(mean(valid_durations), 2L) else NA_real_,
           max_plant_duration_seconds = if (length(valid_durations) > 0L)
               round(max(valid_durations), 2L) else NA_real_,
           min_plant_duration_seconds = if (length(valid_durations) > 0L)
               round(min(valid_durations), 2L) else NA_real_
       )
       metrics
   }

   #' Escreve Metricas em JSON
   #'
   #' Serializa metricas como JSON e escreve em disco. Segue o mesmo
   #' padrao de tratamento de erro de [write_provenance()] -- falhas de
   #' I/O geram apenas aviso no log.
   #'
   #' @param metrics lista de metricas (preferencialmente finalizada)
   #' @param output_dir character, diretorio de saida
   #'
   #' @return caminho do arquivo escrito (invisivelmente)
   write_metrics <- function(metrics, output_dir) {
       lg <- lgr::get_logger("mhpfv")
       filename <- paste0("metrics-", metrics$run_id, ".json")
       filepath <- file.path(output_dir, filename)

       tryCatch({
           if (!dir.exists(output_dir)) {
               dir.create(output_dir, recursive = TRUE)
           }
           json_str <- jsonlite::toJSON(
               metrics, pretty = TRUE, auto_unbox = TRUE, null = "null"
           )
           writeLines(json_str, filepath)
           lg$info("Metricas escritas em: %s", filepath)
       }, error = function(e) {
           lg$warn(
               "Falha ao escrever metricas em '%s': %s",
               filepath, conditionMessage(e)
           )
       })

       invisible(filepath)
   }
   ```

3. **Instrument `train_main()`** in `R/train.r`. Add metrics creation after provenance, timing around plant processing, and model quality recording:

   ```r
   train_main <- function(args, strategy = linear_regression_strategy(),
       parallel = FALSE, resume = FALSE) {

       provenance <- create_provenance(args, "train", parallel)
       metrics <- create_metrics(provenance$run_id, "train")
       # ... (set_log_context from E06-T001, if already implemented)
       # ... (existing resume logic)

       on.exit({
           if (provenance$status == "running") {
               provenance <- finalize_provenance(provenance, "failed")
           }
           write_provenance(provenance, args$artifact)
           metrics <- finalize_metrics(metrics)
           write_metrics(metrics, args$artifact)
       }, add = TRUE)

       # ... (existing data loading and processing)

       # For per-plant timing, wrap the main processing and record in post-processing:
       # Time the entire processing block (parallel or sequential) is not per-plant.
       # For per-plant timing, add timing inside the post-processing lapply:

       plant_start_times <- proc.time()
       # ... (existing parallel/sequential processing to produce `models`)

       # Post-processing with timing and model quality:
       n_total <- length(v_usinas)
       lapply(seq_along(v_usinas), function(i) {
           write_model_artifact(models[[i]], v_usinas[i], args$artifact)
           provenance <<- update_plant_status(provenance, v_usinas[i], "completed")
           if (resume) write_checkpoint(provenance, args$artifact)
           # Record model quality from artifact metadata
           if ("metadata" %in% names(models[[i]])) {
               metrics <<- record_model_quality(
                   metrics, v_usinas[i], models[[i]]$metadata
               )
           }
       })
   }
   ```

   Note on per-plant timing: since `ajustar_usina()` runs either in parallel (via `future_lapply`) or sequentially (via `lapply`), the cleanest approach for timing is to wrap the sequential `lapply` call with per-element `system.time()`, or to measure timing outside the parallel block and divide. A simpler approach: record total processing time as a single metric for the batch, plus use `proc.time()` around the sequential `lapply` to get per-plant write+update timing. For parallel runs, per-plant timing inside workers is not straightforward -- record only the total batch duration and divide by plant count as an estimate.

   The recommended approach: wrap each `ajustar_usina()` call in the **sequential** path with `system.time()`. For the parallel path, record the batch total time and note that per-plant breakdown is unavailable.

   ```r
   if (parallel) {
       batch_start <- proc.time()
       models <- future.apply::future_lapply(v_usinas, ajustar_usina, ...,
           future.seed = TRUE)
       batch_elapsed <- (proc.time() - batch_start)[["elapsed"]]
       # Record estimated per-plant timing
       for (iu in v_usinas) {
           metrics <- record_plant_timing(
               metrics, iu, round(batch_elapsed / length(v_usinas), 2L)
           )
       }
   } else {
       models <- lapply(v_usinas, function(iu) {
           t0 <- proc.time()
           result <- ajustar_usina(iu, ...)
           elapsed <- (proc.time() - t0)[["elapsed"]]
           metrics <<- record_plant_timing(metrics, iu, round(elapsed, 2L))
           result
       })
   }
   ```

4. **Instrument `predict_main()`** similarly, with data volume recording from result data.tables:

   ```r
   # After processing, record data volume for each plant:
   for (i in seq_along(v_usinas_pending)) {
       result <- resultados_new[[i]]
       n_rows <- nrow(result$com_cortes)
       n_na <- sum(is.na(result$com_cortes$valor))
       n_total <- length(result$com_cortes$valor)
       metrics <<- record_plant_data_volume(
           metrics, v_usinas_pending[i], n_rows, n_na, n_total
       )
       # ... (existing provenance update, checkpoint write)
   }
   ```

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/metrics.r` -- **New file** with all metrics collection functions
- `/home/rogerio/git/mh-pfv/R/train.r` -- Add metrics creation, per-plant timing, model quality recording
- `/home/rogerio/git/mh-pfv/R/predict.r` -- Add metrics creation, per-plant timing, data volume recording
- `/home/rogerio/git/mh-pfv/tests/testthat/test-metrics.r` -- **New test file**

### Patterns to Follow

- Copy-on-modify list update pattern from `update_plant_status()` in `R/provenance.r` -- all `record_*` functions return the updated metrics list
- `<<-` assignment in `lapply` callbacks for metrics updates in enclosing scope -- same pattern as provenance updates in `train_main()` and `predict_main()` (documented in learnings)
- `tryCatch` wrapping in `write_metrics()` -- same pattern as `write_provenance()`
- `stopifnot()` input validation -- same pattern as `create_provenance()`, `update_plant_status()`
- File naming: `metrics-{run_id}.json` alongside `provenance-{run_id}.json`
- JSON serialization with `jsonlite::toJSON(..., pretty = TRUE, auto_unbox = TRUE, null = "null")` -- same as `write_provenance()`
- Portuguese log messages and docstrings

### Pitfalls to Avoid

- **Do NOT use `system.time()` for timing** -- it captures CPU time, not wall time. Use `proc.time()[["elapsed"]]` for wall-clock timing, which is more meaningful for pipeline monitoring.
- **Do NOT try to time individual plants inside parallel workers** -- `future_lapply` workers cannot send timing data back to the main process easily. Record batch timing for parallel runs and divide by plant count as an approximation. This is documented in the `pipeline.parallel` field.
- **`<<-` scope** -- when using `<<-` to update `metrics` inside an anonymous function within `lapply`, ensure `metrics` is defined in the enclosing scope of the `lapply` call (i.e., in the function body of `train_main`/`predict_main`), not in a deeper nested scope. The existing `provenance <<-` pattern in these functions demonstrates the correct scope.
- **Do NOT add `metrics.r` functions to NAMESPACE exports** -- these are internal functions. Do not add `@export` roxygen tags. They are called only from `train_main()` and `predict_main()`.
- **JSON serialization of `NA_real_`** -- `jsonlite::toJSON` with `auto_unbox = TRUE` serializes `NA_real_` as `null` in JSON (when `null = "null"` is set). This is the correct behavior for missing metrics.

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-metrics.r`:

1. **`create_metrics()` tests**:
   - Returns correct structure with `run_id`, `mode`, empty `plants` and `pipeline`
   - Validates inputs (non-character run_id errors)

2. **`record_plant_timing()` tests**:
   - Records timing for a single plant; verify `metrics$plants$USI1$duration_seconds`
   - Records timing for multiple plants; verify each entry
   - Validates non-numeric duration raises error

3. **`record_plant_data_volume()` tests**:
   - Records volume with correct `na_rate` calculation
   - Handles `n_total = 0` gracefully (NA rate = NA)

4. **`record_model_quality()` tests**:
   - Records quality from artifact metadata
   - Extracts `n_slots`, `n_valid_slots`, `mean_coefficient`

5. **`finalize_metrics()` tests**:
   - Computes correct aggregates from per-plant timing
   - Handles empty plants list (all aggregates NA)
   - Handles single plant (mean = max = min)
   - Sets `created_at` to ISO 8601 timestamp

6. **`write_metrics()` tests**:
   - Writes valid JSON to temp directory
   - Creates directory if missing
   - Does not throw on I/O failure (test with `/proc/nonexistent/path`)
   - Roundtrip: write then read back and verify structure

### Integration Tests

- After a full `train_main()` integration test (existing in `test-integration-train.r`), verify that `metrics-{run_id}.json` exists in the artifact directory
- After a full `predict_main()` integration test, verify that `metrics-{run_id}.json` exists in the output directory
- `devtools::check()` passes without new issues

## Dependencies

- **Blocked By**: E04-T002 (run provenance -- completed)
- **Blocks**: E06-T003

## Effort Estimate

**Points**: 3
**Confidence**: High
