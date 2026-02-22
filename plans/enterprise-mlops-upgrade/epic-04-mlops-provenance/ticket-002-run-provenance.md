# E04-T002 Add Run Provenance Tracking

## Context

### Background

The mhpfv pipeline currently runs with no record of execution metadata. When `train_main()` or `predict_main()` completes, there is no audit trail of what inputs were used, when the run started/ended, how many plants were processed, or whether any failures occurred. For production ML pipelines operated by ONS (Brazilian national grid operator), this is a critical gap -- every pipeline execution must be traceable and auditable.

This ticket introduces a provenance tracking system that wraps pipeline executions with metadata capture and writes a JSON provenance file alongside outputs.

### Relation to Epic

This is the second ticket in Epic 04 (MLOps and Provenance). It establishes the provenance infrastructure that E04-T003 (pipeline resume) will extend with checkpoint state, and provides the run-level context that complements the artifact-level metadata from E04-T001.

### Current State

**Pipeline entry points** (`/home/rogerio/git/mh-pfv/R/cli.r`, lines 14-33):

```r
cli_main <- function(datadir = "./data") {
    lg <- get_pkg_logger()
    conn <- conectamock_pfv(datadir)
    config <- get_config(conn)
    config <- parse_config(config, conn)
    if (config$mode == "train") {
        train_main(config)
    } else if (config$mode == "predict") {
        predict_main(config)
    } else {
        stop("Modo invalido. ...")
    }
    invisible(0L)
}
```

**Train pipeline** (`/home/rogerio/git/mh-pfv/R/train.r`, lines 51-92): processes `v_usinas` via `lapply`/`future_lapply`, writes artifacts sequentially. Returns nothing (invisible).

**Predict pipeline** (`/home/rogerio/git/mh-pfv/R/predict.r`, lines 49-108): processes `v_usinas`, organizes results, writes two parquet files to `args$output`. Returns nothing (invisible).

**Output writing** (`/home/rogerio/git/mh-pfv/R/escrita.r`): writes `melhor_historico_geracao.parquet` and `melhor_historico_geracao_sem_cortes.parquet` to `output_dir`.

**No provenance exists today**: there are no JSON files, no run IDs, no timestamps, and no checksums anywhere in the pipeline output.

**Dependencies available**: `jsonlite` is not in DESCRIPTION but is a standard R package (part of many base installations). `digest` will be added by E04-T001.

## Specification

### Requirements

1. **Create `R/provenance.r`**: A new file containing all provenance-related functions.

2. **Run ID generation**: `generate_run_id()` produces a unique identifier in the format `{mode}-{YYYYMMDD}-{HHMMSS}-{4hex}` (e.g., `train-20260217-143052-a1b2`). The 4-hex suffix is generated from `sample()` with the PID as part of the seed to ensure uniqueness across concurrent runs.

3. **Provenance record creation**: `create_provenance(config, mode)` creates a provenance record (a plain list) with:
   - `run_id`: unique run ID
   - `mode`: "train" or "predict"
   - `package_version`: mhpfv version
   - `r_version`: R version string
   - `start_time`: POSIXct timestamp (set at creation)
   - `end_time`: NULL (set at finalization)
   - `duration_seconds`: NULL (computed at finalization)
   - `config_hash`: sha256 hash of the config (using `normalize_config_for_hash()` from E04-T001's `R/artifact.r`)
   - `n_plants`: number of plants to process
   - `plant_ids`: character vector of plant IDs
   - `plant_status`: named list, one entry per plant, initially all `"pending"`
   - `parallel`: logical, whether parallel mode was used
   - `status`: "running" (set to "completed" or "failed" at finalization)

4. **Plant status tracking**: `update_plant_status(provenance, id_usina, status)` updates the plant's status in the provenance record. Status values: `"completed"`, `"failed"`, `"skipped"`. Returns the updated provenance record.

5. **Finalization**: `finalize_provenance(provenance, status)` sets `end_time`, computes `duration_seconds`, sets overall `status` ("completed" or "failed").

6. **Provenance writing**: `write_provenance(provenance, output_dir)` writes the provenance record as a JSON file to `{output_dir}/provenance-{run_id}.json`. Uses `jsonlite::toJSON()` with `pretty = TRUE` and `auto_unbox = TRUE`.

7. **Wire into pipelines**: Both `train_main()` and `predict_main()` must:
   - Create a provenance record at the start
   - Update plant status as each plant completes (in the sequential artifact-writing loop for train, or by inspecting results for predict)
   - Finalize and write provenance at the end
   - Use `on.exit()` to ensure provenance is written even if the pipeline fails partway

8. **Add `jsonlite` to Imports**: Add to DESCRIPTION.

### Inputs/Props

- `generate_run_id(mode)`: character mode string ("train"/"predict")
- `create_provenance(config, mode, parallel)`: config list, mode string, parallel logical
- `update_plant_status(provenance, id_usina, status)`: provenance list, plant ID, status string
- `finalize_provenance(provenance, status)`: provenance list, overall status string
- `write_provenance(provenance, output_dir)`: provenance list, output directory path

### Outputs/Behavior

- `generate_run_id()` returns a character string
- `create_provenance()` returns a provenance list
- `update_plant_status()` returns the modified provenance list (R lists are copy-on-modify)
- `finalize_provenance()` returns the finalized provenance list
- `write_provenance()` writes JSON and returns `invisible(file_path)`
- Provenance JSON example:
  ```json
  {
    "run_id": "train-20260217-143052-a1b2",
    "mode": "train",
    "package_version": "0.1.1",
    "r_version": "4.4.1",
    "start_time": "2026-02-17T14:30:52Z",
    "end_time": "2026-02-17T14:31:15Z",
    "duration_seconds": 23.4,
    "config_hash": "sha256:abc123...",
    "n_plants": 2,
    "plant_ids": ["BAUFI1", "BAUFI2"],
    "plant_status": {
      "BAUFI1": "completed",
      "BAUFI2": "completed"
    },
    "parallel": false,
    "status": "completed"
  }
  ```

### Error Handling

- `write_provenance()` must not throw on directory creation failure -- wrap in `tryCatch` and log a warning if the provenance file cannot be written. The pipeline must not fail because of provenance writing failure.
- `on.exit(write_provenance(...))` in both pipelines ensures provenance is written even on pipeline failure. If the pipeline fails, `status` is set to "failed" and `end_time` captures when the failure occurred.
- For train mode, the provenance output directory is `args$artifact` (alongside model artifacts). For predict mode, it is `args$output` (alongside parquet outputs).
- All error and warning messages in Portuguese.

## Acceptance Criteria

- [ ] Given a call to `generate_run_id("train")`, when inspected, then the returned string matches the pattern `^train-\\d{8}-\\d{6}-[0-9a-f]{4}$`
- [ ] Given two calls to `generate_run_id("train")` separated by at least 1 second, when compared, then the run IDs are different
- [ ] Given a valid config and mode, when `create_provenance(config, "train", FALSE)` is called, then the returned list has all required fields with correct initial values (status = "running", end_time = NULL, all plants "pending")
- [ ] Given a provenance record, when `update_plant_status(prov, "BAUFI1", "completed")` is called, then `prov$plant_status$BAUFI1` is "completed" in the returned record
- [ ] Given a running provenance record, when `finalize_provenance(prov, "completed")` is called, then `end_time` is set, `duration_seconds` is positive, and `status` is "completed"
- [ ] Given a finalized provenance record, when `write_provenance(prov, tempdir())` is called, then a JSON file `provenance-{run_id}.json` exists in the output directory and is valid JSON parseable by `jsonlite::fromJSON()`
- [ ] Given `train_main()` is executed with test data, when it completes, then a `provenance-*.json` file is written to the artifact directory
- [ ] Given `predict_main()` is executed with test data, when it completes, then a `provenance-*.json` file is written to the output directory
- [ ] Given a pipeline execution that fails partway, when the error propagates, then a provenance file is still written with `status = "failed"` and partial plant statuses
- [ ] Given `devtools::check()` is run, then no missing dependency warnings for `jsonlite`

## Implementation Guide

### Suggested Approach

**Step 1: Add `jsonlite` dependency**

In `/home/rogerio/git/mh-pfv/DESCRIPTION`, add `jsonlite (>= 1.8.0)` to Imports.

**Step 2: Create `R/provenance.r`**

```r
#' Gera Identificador Unico de Execucao
#'
#' @param mode character, "train" ou "predict"
#'
#' @return character com o run ID no formato "{mode}-{YYYYMMDD}-{HHMMSS}-{4hex}"
#'
#' @export
generate_run_id <- function(mode) {
    stopifnot(is.character(mode), length(mode) == 1L)
    ts <- format(Sys.time(), "%Y%m%d-%H%M%S")
    hex <- paste0(
        sprintf("%x", sample(0:15, 4, replace = TRUE)),
        collapse = ""
    )
    paste0(mode, "-", ts, "-", hex)
}

#' Cria Registro de Proveniencia de Execucao
#'
#' @param config lista com a configuracao do pipeline
#' @param mode character, "train" ou "predict"
#' @param parallel logico, se a execucao e paralela
#'
#' @return lista com todos os campos de proveniencia
#'
#' @export
create_provenance <- function(config, mode, parallel = FALSE) {
    run_id <- generate_run_id(mode)

    plant_ids <- config$ids_usinas
    plant_status <- as.list(rep("pending", length(plant_ids)))
    names(plant_status) <- plant_ids

    list(
        run_id = run_id,
        mode = mode,
        package_version = as.character(utils::packageVersion("mhpfv")),
        r_version = paste0(R.version$major, ".", R.version$minor),
        start_time = Sys.time(),
        end_time = NULL,
        duration_seconds = NULL,
        config_hash = digest::digest(
            normalize_config_for_hash(config),
            algo = "sha256"
        ),
        n_plants = length(plant_ids),
        plant_ids = plant_ids,
        plant_status = plant_status,
        parallel = parallel,
        status = "running"
    )
}

#' Atualiza Status de Uma Usina no Registro de Proveniencia
#'
#' @param provenance lista de proveniencia
#' @param id_usina character, identificador da usina
#' @param status character, "completed", "failed" ou "skipped"
#'
#' @return lista de proveniencia atualizada
#'
#' @export
update_plant_status <- function(provenance, id_usina, status) {
    valid_status <- c("completed", "failed", "skipped")
    stopifnot(
        is.list(provenance),
        is.character(id_usina), length(id_usina) == 1L,
        is.character(status), length(status) == 1L,
        status %in% valid_status
    )
    provenance$plant_status[[id_usina]] <- status
    provenance
}

#' Finaliza Registro de Proveniencia
#'
#' @param provenance lista de proveniencia
#' @param status character, "completed" ou "failed"
#'
#' @return lista de proveniencia finalizada
#'
#' @export
finalize_provenance <- function(provenance, status = "completed") {
    stopifnot(
        is.list(provenance),
        status %in% c("completed", "failed")
    )
    provenance$end_time <- Sys.time()
    provenance$duration_seconds <- as.numeric(
        difftime(provenance$end_time, provenance$start_time, units = "secs")
    )
    provenance$status <- status
    provenance
}

#' Escreve Registro de Proveniencia em JSON
#'
#' @param provenance lista de proveniencia finalizada
#' @param output_dir character, diretorio de saida
#'
#' @return caminho do arquivo escrito (invisivelmente)
#'
#' @export
write_provenance <- function(provenance, output_dir) {
    lg <- lgr::get_logger("mhpfv")

    filename <- paste0("provenance-", provenance$run_id, ".json")
    filepath <- file.path(output_dir, filename)

    tryCatch({
        if (!dir.exists(output_dir)) {
            dir.create(output_dir, recursive = TRUE)
        }

        # Converte POSIXct para ISO 8601 strings para JSON
        prov_json <- provenance
        prov_json$start_time <- format(
            provenance$start_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
        )
        if (!is.null(provenance$end_time)) {
            prov_json$end_time <- format(
                provenance$end_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
            )
        }

        json_str <- jsonlite::toJSON(prov_json, pretty = TRUE,
            auto_unbox = TRUE, null = "null")
        writeLines(json_str, filepath)

        lg$info("Proveniencia escrita em: %s", filepath)
    }, error = function(e) {
        lg$warn(
            "Falha ao escrever proveniencia em '%s': %s",
            filepath, conditionMessage(e)
        )
    })

    invisible(filepath)
}
```

**Step 3: Wire provenance into `train_main()`**

In `/home/rogerio/git/mh-pfv/R/train.r`, modify `train_main()`:

```r
train_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE) {

    provenance <- create_provenance(args, "train", parallel)
    output_dir <- args$artifact
    on.exit({
        if (provenance$status == "running") {
            provenance <- finalize_provenance(provenance, "failed")
        }
        write_provenance(provenance, output_dir)
    }, add = TRUE)

    # ... existing pipeline code ...

    # After artifact writing loop, update plant statuses:
    lapply(seq_along(v_usinas), function(i) {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
        provenance <<- update_plant_status(
            provenance, v_usinas[i], "completed"
        )
    })

    provenance <- finalize_provenance(provenance, "completed")
}
```

**Step 4: Wire provenance into `predict_main()`**

In `/home/rogerio/git/mh-pfv/R/predict.r`, modify `predict_main()` similarly:

```r
predict_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE) {

    provenance <- create_provenance(args, "predict", parallel)
    on.exit({
        if (provenance$status == "running") {
            provenance <- finalize_provenance(provenance, "failed")
        }
        write_provenance(provenance, args$output)
    }, add = TRUE)

    # ... existing pipeline code ...

    # After results are organized and written, mark all plants completed:
    for (iu in v_usinas) {
        provenance <- update_plant_status(provenance, iu, "completed")
    }

    # ... write outputs ...

    provenance <- finalize_provenance(provenance, "completed")
}
```

**Step 5: Update NAMESPACE**

Run `devtools::document()` to export the new functions.

### Key Files to Modify

| File                                                        | Change                                                       |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| `/home/rogerio/git/mh-pfv/DESCRIPTION`                      | Add `jsonlite (>= 1.8.0)` to Imports                         |
| `/home/rogerio/git/mh-pfv/R/provenance.r`                   | **NEW FILE** -- all provenance functions                     |
| `/home/rogerio/git/mh-pfv/R/train.r`                        | Wire provenance creation, plant status updates, finalization |
| `/home/rogerio/git/mh-pfv/R/predict.r`                      | Wire provenance creation, plant status updates, finalization |
| `/home/rogerio/git/mh-pfv/tests/testthat/test-provenance.r` | **NEW FILE** -- tests for provenance functions               |
| `/home/rogerio/git/mh-pfv/NAMESPACE`                        | Regenerated by `devtools::document()`                        |

### Patterns to Follow

- **`on.exit()` for cleanup**: Follow the parallel plan cleanup pattern in `train_main()` (line 66): `on.exit(reset_parallel_plan(old_plan), add = TRUE)`. Use `add = TRUE` to stack with existing on.exit handlers.
- **Error collection pattern**: Follow `validate_input()` in `R/validation.r` for `stopifnot` style validation.
- **Logging via lgr**: Use `lgr::get_logger("mhpfv")` for all log messages, matching existing usage throughout the codebase.
- **Portuguese messages**: All user-facing strings in Portuguese.
- **`normalize_config_for_hash()`**: Reuse the function from `R/artifact.r` (created in E04-T001) for config hashing.

### Pitfalls to Avoid

- **`provenance <<-` in `lapply`**: The `<<-` operator is needed to update the provenance in the enclosing scope from within `lapply`. This is a common R pattern but can surprise developers. Document it with a comment.
- **`on.exit` ordering with parallel cleanup**: If `parallel = TRUE`, both the parallel plan cleanup and provenance writing use `on.exit`. Use `add = TRUE` on both to ensure they stack. The provenance `on.exit` should be registered BEFORE the parallel plan `on.exit` so it runs AFTER (LIFO order).
- **Do NOT try to track per-plant timing in parallel mode**: In parallel mode, plants are processed concurrently. Tracking per-plant start/end times would require modifying the worker functions. Keep it simple -- just track completion status, not timing.
- **JSON timestamp serialization**: `jsonlite::toJSON()` serializes POSIXct as epoch numbers by default. Convert to ISO 8601 strings explicitly before serialization.
- **`write_provenance` must not crash the pipeline**: Wrap in `tryCatch` -- if the output directory is read-only or full, log a warning but let the pipeline complete normally.
- **Do not checksum input files**: The original outline suggested checksumming input Parquet files. This would add significant I/O overhead and is not needed for the initial implementation. The `config_hash` captures the configuration identity, which is sufficient for auditability. File checksumming can be added later as an enhancement.

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-provenance.r`:

1. **`generate_run_id` format**: Verify pattern matches `^(train|predict)-\\d{8}-\\d{6}-[0-9a-f]{4}$`.
2. **`generate_run_id` uniqueness**: Generate 100 IDs and verify all are unique.
3. **`generate_run_id` validates mode**: Pass non-character, verify error.
4. **`create_provenance` structure**: Given `gen_config()`, verify all fields are present with correct initial values.
5. **`create_provenance` plant_status initialization**: Verify all plants start as "pending".
6. **`update_plant_status` updates correctly**: Update one plant, verify only that plant changed.
7. **`update_plant_status` validates status values**: Pass invalid status string, verify error.
8. **`finalize_provenance` sets timing**: Verify `end_time` is set, `duration_seconds` is positive.
9. **`finalize_provenance` sets status**: Verify "completed" and "failed" both work.
10. **`write_provenance` creates valid JSON**: Write to `withr::local_tempdir()`, read back with `jsonlite::fromJSON()`, verify all fields are present.
11. **`write_provenance` handles missing directory**: Write to non-existent subdirectory of `withr::local_tempdir()`, verify it creates the directory.
12. **`write_provenance` does not throw on failure**: Mock a read-only directory (skip on CI if needed), verify it logs a warning but does not error.

### Integration Tests

1. **Train pipeline writes provenance**: Using test data at `tests/testthat/data/` with `janela = list("2025-07-01", "2025-09-30")`, run `train_main()` with artifact dir in `withr::local_tempdir()`. Verify `provenance-*.json` file exists, is valid JSON, and has `status = "completed"`.
2. **Predict pipeline writes provenance**: Run full train + predict cycle, verify provenance JSON in output directory.

## Dependencies

- **Blocked By**: E04-T001 (uses `normalize_config_for_hash()` and `digest` dependency)
- **Blocks**: E04-T003 (pipeline resume extends provenance with checkpoint state)

## Effort Estimate

**Points**: 3
**Confidence**: High
