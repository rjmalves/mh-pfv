# E06-T003 Create Pipeline Health Report

## Context

### Background

The mhpfv pipeline currently produces two types of execution records: `provenance-{run_id}.json` (high-level execution metadata with per-plant status, timing, and config hash) and -- after E06-T002 -- `metrics-{run_id}.json` (per-plant timing, data volumes, and model quality indicators). These files capture raw execution data but do not provide a consolidated health assessment that operators or monitoring systems can consume to quickly determine whether a pipeline run was healthy, degraded, or failed.

ONS operators need a single report file per run that answers: "Did this run succeed? Were there data quality issues? Are the models reasonable? How does this run compare to expectations?" This ticket creates a health report generator that aggregates provenance and metrics into a structured JSON summary with explicit health indicators and status classifications.

### Relation to Epic

This ticket is the capstone of Epic 06 (Observability and Monitoring). It consumes the structured logging context from E06-T001 and the metrics data from E06-T002, synthesizing them into a production-ready health report. The report is the primary artifact that external monitoring systems (out of scope for this epic) would consume.

### Current State

**`R/provenance.r`** -- Provenance record structure (available after E04-T002, completed):

```r
# Provenance fields:
# run_id, mode, package_version, r_version, start_time, end_time,
# duration_seconds, config_hash, n_plants, plant_ids, plant_status,
# parallel, status
```

The `plant_status` field is a named list mapping plant IDs to `"completed"`, `"failed"`, or `"skipped"`. The `status` field is `"completed"` or `"failed"`.

**`R/metrics.r`** (created by E06-T002) -- Metrics record structure:

```json
{
  "run_id": "...",
  "mode": "...",
  "pipeline": {
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

**`R/train.r` and `R/predict.r`** -- Pipeline functions produce provenance and metrics, but no health report.

**No health report file is produced today.**

## Specification

### Requirements

1. **Create `R/health-report.r`** with a health report generator that:
   - Builds a health report from a finalized provenance record and finalized metrics record
   - Classifies overall pipeline health as `"healthy"`, `"degraded"`, or `"failed"`
   - Classifies per-plant health based on completion status and data quality indicators
   - Writes the report as `health-{run_id}.json`

2. **Health classification rules**:
   - **Overall status**:
     - `"healthy"`: provenance `status == "completed"` AND all plants completed AND no plant has `na_rate > 0.5`
     - `"degraded"`: provenance `status == "completed"` BUT some plants have `na_rate > 0.5` OR some plants have model quality issues (train mode: `n_valid_slots < n_slots * 0.5`)
     - `"failed"`: provenance `status == "failed"` OR any plant has `plant_status == "failed"`
   - **Per-plant status**:
     - `"healthy"`: completed AND (`na_rate <= 0.5` or no data_volume recorded) AND (no model_quality or `n_valid_slots >= n_slots * 0.5`)
     - `"warning"`: completed BUT `na_rate > 0.5` OR `n_valid_slots < n_slots * 0.5`
     - `"failed"`: plant_status is `"failed"` in provenance

3. **Health report JSON format**:

   ```json
   {
     "run_id": "train-20260222-143052-a1b2",
     "mode": "train",
     "created_at": "2026-02-22T14:32:00Z",
     "overall_health": "healthy",
     "summary": {
       "status": "completed",
       "duration_seconds": 42.5,
       "n_plants": 5,
       "n_plants_completed": 5,
       "n_plants_failed": 0,
       "n_plants_warning": 0,
       "package_version": "0.1.1",
       "config_hash": "abc123..."
     },
     "plants": {
       "BAUFI1": {
         "health": "healthy",
         "provenance_status": "completed",
         "duration_seconds": 8.5,
         "data_quality": {
           "na_rate": 0.0833,
           "n_rows": 1440
         },
         "model_quality": {
           "n_slots": 28,
           "n_valid_slots": 26,
           "mean_coefficient": 0.031
         }
       }
     },
     "warnings": [],
     "errors": []
   }
   ```

4. **Integrate into pipeline** -- call `build_health_report()` and `write_health_report()` in the `on.exit()` block of both `train_main()` and `predict_main()`, after provenance and metrics are finalized.

### Inputs/Props

| Function                                                  | Parameters                                                  | Description                                      |
| --------------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------ |
| `build_health_report(provenance, metrics)`                | `provenance` list (finalized), `metrics` list (finalized)   | Builds health report from provenance and metrics |
| `classify_overall_health(provenance, plant_healths)`      | `provenance` list, `plant_healths` named character vector   | Returns `"healthy"`, `"degraded"`, or `"failed"` |
| `classify_plant_health(provenance_status, plant_metrics)` | `provenance_status` character, `plant_metrics` list or NULL | Returns `"healthy"`, `"warning"`, or `"failed"`  |
| `write_health_report(report, output_dir)`                 | `report` list, `output_dir` character                       | Writes `health-{run_id}.json`                    |

### Outputs/Behavior

- `build_health_report()` returns a list with the structure shown in the JSON format above. It extracts data from both provenance and metrics, classifies health, and populates warnings/errors lists.
- `classify_overall_health()` applies the classification rules to determine overall pipeline health.
- `classify_plant_health()` applies per-plant classification rules based on provenance status and metrics data.
- `write_health_report()` serializes to JSON and writes `health-{run_id}.json`. Same error-handling pattern as `write_provenance()`.
- The `warnings` array collects human-readable warning strings in Portuguese (e.g., "Usina BAUFI1: taxa de NA elevada (83.3%)", "Usina BAUFI2: apenas 12 de 28 slots com coeficiente valido").
- The `errors` array collects error strings for failed plants (e.g., "Usina BAUFI3: processamento falhou").

### Error Handling

- `build_health_report()` handles missing or incomplete metrics gracefully. If `metrics` is `NULL` or has no plant entries, the report is still generated using provenance data alone, with `data_quality` and `model_quality` set to `NULL` for each plant.
- `write_health_report()` is wrapped in `tryCatch` -- I/O failures log a warning and do not crash the pipeline (same pattern as `write_provenance()`).
- If provenance is not finalized (status is still `"running"`), `build_health_report()` treats it as `"failed"` and logs a warning.

## Acceptance Criteria

- [ ] Given a completed `train_main()` run with all plants successful, when `build_health_report()` is called, then `overall_health` is `"healthy"`
- [ ] Given a completed run where one plant has `na_rate > 0.5`, when the report is built, then `overall_health` is `"degraded"` and that plant's health is `"warning"`
- [ ] Given a failed run (provenance status `"failed"`), when the report is built, then `overall_health` is `"failed"`
- [ ] Given a completed run, when the report is built, then the `warnings` array contains a Portuguese message for each plant with elevated NA rate or low valid slot count
- [ ] Given a `train_main()` run, when it completes, then `health-{run_id}.json` exists alongside `provenance-{run_id}.json` and `metrics-{run_id}.json` in the artifact directory
- [ ] Given a `predict_main()` run, when it completes, then `health-{run_id}.json` exists in the output directory
- [ ] Given `build_health_report()` called with `metrics = NULL`, when it returns, then the report contains provenance data with `data_quality` and `model_quality` as `NULL` for each plant
- [ ] Given `write_health_report()` called with an invalid output directory, when it fails, then no error propagates (only a log warning)
- [ ] Given `devtools::check()` is run, when checks complete, then no new NOTEs, WARNINGs, or ERRORs are introduced

## Implementation Guide

### Suggested Approach

1. **Create `R/health-report.r`** with the health report functions:

   ```r
   #' Constroi Relatorio de Saude do Pipeline
   #'
   #' Agrega dados de proveniencia e metricas em um relatorio estruturado
   #' com classificacao de saude por usina e do pipeline como um todo.
   #'
   #' @param provenance lista de proveniencia finalizada
   #' @param metrics lista de metricas finalizada, ou NULL
   #'
   #' @return lista com o relatorio de saude completo
   build_health_report <- function(provenance, metrics = NULL) {
       stopifnot(is.list(provenance))

       lg <- lgr::get_logger("mhpfv")
       if (provenance$status == "running") {
           lg$warn("Relatorio de saude gerado com proveniencia nao finalizada")
       }

       plant_reports <- build_plant_reports(provenance, metrics)
       plant_healths <- vapply(
           plant_reports,
           function(p) p$health,
           character(1L)
       )

       overall <- classify_overall_health(provenance, plant_healths)
       warnings_list <- collect_warnings(plant_reports)
       errors_list <- collect_errors(plant_reports)

       list(
           run_id = provenance$run_id,
           mode = provenance$mode,
           created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
           overall_health = overall,
           summary = list(
               status = provenance$status,
               duration_seconds = provenance$duration_seconds,
               n_plants = provenance$n_plants,
               n_plants_completed = sum(plant_healths != "failed"),
               n_plants_failed = sum(plant_healths == "failed"),
               n_plants_warning = sum(plant_healths == "warning"),
               package_version = provenance$package_version,
               config_hash = provenance$config_hash
           ),
           plants = plant_reports,
           warnings = warnings_list,
           errors = errors_list
       )
   }
   ```

2. **Implement helper functions** for plant-level reports and classification:

   ```r
   build_plant_reports <- function(provenance, metrics) {
       reports <- list()
       for (iu in provenance$plant_ids) {
           prov_status <- provenance$plant_status[[iu]]
           if (is.null(prov_status)) prov_status <- "pending"

           plant_metrics <- if (!is.null(metrics)) metrics$plants[[iu]] else NULL

           data_quality <- NULL
           if (!is.null(plant_metrics$data_volume)) {
               data_quality <- list(
                   na_rate = plant_metrics$data_volume$na_rate,
                   n_rows = plant_metrics$data_volume$n_rows
               )
           }

           model_quality <- NULL
           if (!is.null(plant_metrics$model_quality)) {
               model_quality <- plant_metrics$model_quality
           }

           health <- classify_plant_health(prov_status, plant_metrics)

           reports[[iu]] <- list(
               health = health,
               provenance_status = prov_status,
               duration_seconds = plant_metrics$duration_seconds,
               data_quality = data_quality,
               model_quality = model_quality
           )
       }
       reports
   }

   #' Classifica Saude de Uma Usina
   #'
   #' @param provenance_status character, status da usina na proveniencia
   #' @param plant_metrics lista de metricas da usina, ou NULL
   #'
   #' @return character: "healthy", "warning", ou "failed"
   classify_plant_health <- function(provenance_status, plant_metrics) {
       if (provenance_status == "failed") return("failed")
       if (provenance_status != "completed") return("failed")

       # Check data quality
       if (!is.null(plant_metrics$data_volume)) {
           na_rate <- plant_metrics$data_volume$na_rate
           if (!is.na(na_rate) && na_rate > 0.5) return("warning")
       }

       # Check model quality (train mode)
       if (!is.null(plant_metrics$model_quality)) {
           mq <- plant_metrics$model_quality
           if (!is.null(mq$n_slots) && !is.null(mq$n_valid_slots)) {
               if (mq$n_valid_slots < mq$n_slots * 0.5) return("warning")
           }
       }

       "healthy"
   }

   #' Classifica Saude Geral do Pipeline
   #'
   #' @param provenance lista de proveniencia
   #' @param plant_healths character vector de saude por usina
   #'
   #' @return character: "healthy", "degraded", ou "failed"
   classify_overall_health <- function(provenance, plant_healths) {
       if (provenance$status == "failed") return("failed")
       if (any(plant_healths == "failed")) return("failed")
       if (any(plant_healths == "warning")) return("degraded")
       "healthy"
   }
   ```

3. **Implement warning and error collection**:

   ```r
   collect_warnings <- function(plant_reports) {
       warnings_list <- character(0L)
       for (iu in names(plant_reports)) {
           p <- plant_reports[[iu]]
           if (p$health != "warning") next

           if (!is.null(p$data_quality) && !is.na(p$data_quality$na_rate) &&
               p$data_quality$na_rate > 0.5) {
               warnings_list <- c(warnings_list, sprintf(
                   "Usina %s: taxa de NA elevada (%.1f%%)",
                   iu, p$data_quality$na_rate * 100
               ))
           }

           if (!is.null(p$model_quality)) {
               mq <- p$model_quality
               if (!is.null(mq$n_slots) && !is.null(mq$n_valid_slots) &&
                   mq$n_valid_slots < mq$n_slots * 0.5) {
                   warnings_list <- c(warnings_list, sprintf(
                       "Usina %s: apenas %d de %d slots com coeficiente valido",
                       iu, mq$n_valid_slots, mq$n_slots
                   ))
               }
           }
       }
       warnings_list
   }

   collect_errors <- function(plant_reports) {
       errors_list <- character(0L)
       for (iu in names(plant_reports)) {
           if (plant_reports[[iu]]$health == "failed") {
               errors_list <- c(errors_list, sprintf(
                   "Usina %s: processamento falhou", iu
               ))
           }
       }
       errors_list
   }
   ```

4. **Implement `write_health_report()`**:

   ```r
   #' Escreve Relatorio de Saude em JSON
   #'
   #' Serializa relatorio como JSON e escreve em disco. Segue o mesmo
   #' padrao de tratamento de erro de [write_provenance()].
   #'
   #' @param report lista com o relatorio de saude
   #' @param output_dir character, diretorio de saida
   #'
   #' @return caminho do arquivo escrito (invisivelmente)
   write_health_report <- function(report, output_dir) {
       lg <- lgr::get_logger("mhpfv")
       filename <- paste0("health-", report$run_id, ".json")
       filepath <- file.path(output_dir, filename)

       tryCatch({
           if (!dir.exists(output_dir)) {
               dir.create(output_dir, recursive = TRUE)
           }
           json_str <- jsonlite::toJSON(
               report, pretty = TRUE, auto_unbox = TRUE, null = "null"
           )
           writeLines(json_str, filepath)
           lg$info("Relatorio de saude escrito em: %s", filepath)
       }, error = function(e) {
           lg$warn(
               "Falha ao escrever relatorio de saude em '%s': %s",
               filepath, conditionMessage(e)
           )
       })

       invisible(filepath)
   }
   ```

5. **Integrate into `train_main()` and `predict_main()`** -- add health report generation to the `on.exit()` blocks, after metrics finalization:

   ```r
   on.exit({
       if (provenance$status == "running") {
           provenance <- finalize_provenance(provenance, "failed")
       }
       write_provenance(provenance, args$artifact)  # or args$output for predict
       metrics <- finalize_metrics(metrics)
       write_metrics(metrics, args$artifact)
       report <- build_health_report(provenance, metrics)
       write_health_report(report, args$artifact)
   }, add = TRUE)
   ```

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/health-report.r` -- **New file** with all health report functions
- `/home/rogerio/git/mh-pfv/R/train.r` -- Add health report generation to `on.exit()` block
- `/home/rogerio/git/mh-pfv/R/predict.r` -- Add health report generation to `on.exit()` block
- `/home/rogerio/git/mh-pfv/tests/testthat/test-health-report.r` -- **New test file**

### Patterns to Follow

- `tryCatch` in `write_health_report()` -- same pattern as `write_provenance()` and `write_metrics()`
- `stopifnot()` input validation -- same pattern as all Epic 04 functions
- JSON serialization with `jsonlite::toJSON(..., pretty = TRUE, auto_unbox = TRUE, null = "null")` -- consistent with provenance and metrics
- File naming: `health-{run_id}.json` alongside `provenance-{run_id}.json` and `metrics-{run_id}.json`
- Non-exported internal functions documented with roxygen2 but no `@export` -- consistent with `format_provenance_timestamps()`, `validate_comparison_input()`, etc.
- Portuguese for all messages, warnings, and errors
- `gen_config()` from `tests/testthat/helper-generators.r` for test fixtures
- `withr::local_tempdir()` for temp directories in tests

### Pitfalls to Avoid

- **Health report depends on metrics being finalized** -- `build_health_report()` receives already-finalized provenance and metrics. Do not call it before `finalize_provenance()` and `finalize_metrics()`. The `on.exit()` block ordering is critical: finalize provenance first, then metrics, then build health report.
- **`metrics` can be `NULL`** -- if E06-T002 is not yet implemented or if metrics collection fails, `build_health_report()` must still work with only provenance data. All plant `data_quality` and `model_quality` fields should be `NULL` in this case.
- **`plant_status` values from provenance read from JSON** -- when reading a provenance file from disk (not from the in-memory provenance object), `plant_status` values might be character strings. The classification functions must handle both `"completed"` (character) and `"completed"` (from in-memory list).
- **Do NOT use `expect_warning()` for lgr log messages** -- lgr messages are not R conditions. Test logger behavior by inspecting logger fields or using `AppenderBuffer`.
- **Empty `warnings` and `errors` arrays** -- `jsonlite::toJSON` serializes `character(0L)` as `[]` in JSON when `auto_unbox = TRUE`, which is the correct behavior. Do not convert to `list()` -- `character(0L)` is correct.
- **NA values in JSON** -- `jsonlite::toJSON` with `null = "null"` serializes `NA_real_` as `null`. This is correct for missing duration, data_quality, or model_quality fields.

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-health-report.r`:

1. **`classify_plant_health()` tests**:
   - Returns `"failed"` for `provenance_status == "failed"`
   - Returns `"healthy"` for completed plant with no quality issues
   - Returns `"warning"` for completed plant with `na_rate > 0.5`
   - Returns `"warning"` for completed plant with `n_valid_slots < n_slots * 0.5`
   - Returns `"healthy"` for completed plant with `NULL` metrics

2. **`classify_overall_health()` tests**:
   - Returns `"healthy"` when all plants healthy and provenance completed
   - Returns `"degraded"` when some plants have warnings but none failed
   - Returns `"failed"` when provenance status is `"failed"`
   - Returns `"failed"` when any plant health is `"failed"`

3. **`build_health_report()` tests**:
   - Returns complete structure with all expected fields
   - Correctly aggregates per-plant reports into summary counts
   - Handles `metrics = NULL` gracefully
   - Populates `warnings` array for plants with elevated NA rates
   - Populates `errors` array for failed plants

4. **`collect_warnings()` tests**:
   - Returns Portuguese warning messages for plants with quality issues
   - Returns empty character vector when no warnings

5. **`collect_errors()` tests**:
   - Returns Portuguese error messages for failed plants
   - Returns empty character vector when no errors

6. **`write_health_report()` tests**:
   - Writes valid JSON to temp directory
   - Creates directory if missing
   - Does not throw on I/O failure
   - Roundtrip: write then read back and verify structure

### Integration Tests

- After a full `train_main()` integration test, verify `health-{run_id}.json` exists and contains `overall_health` field
- `devtools::check()` passes without new issues

## Dependencies

- **Blocked By**: E06-T002
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
