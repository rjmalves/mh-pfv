# E04-T003 Implement Pipeline Resume on Failure

## Context

### Background

In production, the mhpfv pipeline processes hundreds of solar plants sequentially (or in parallel batches). If the pipeline fails on plant 150 of 400, all 149 successfully processed plants' work is lost -- the operator must restart from scratch. This is particularly painful for the predict pipeline, which reads model artifacts, runs two gap-filling passes per plant, and writes large parquet outputs.

This ticket introduces a checkpoint/resume mechanism: the pipeline writes per-plant completion status to a state file as it progresses, and on restart, it can skip plants that were already successfully processed.

### Relation to Epic

This is the third ticket in Epic 04. It extends the provenance system from E04-T002 by adding persistent checkpoint state. The provenance record already tracks `plant_status` per plant in memory -- this ticket persists that state to disk and adds resume detection logic at pipeline start.

### Current State

**Train pipeline loop** (`/home/rogerio/git/mh-pfv/R/train.r`, lines 64-91):

```r
# Parallel or sequential plant processing:
if (parallel) {
    models <- future.apply::future_lapply(v_usinas, ajustar_usina, ...)
} else {
    models <- lapply(v_usinas, ajustar_usina, ...)
}

# Sequential artifact writing:
lapply(seq_along(v_usinas), function(i) {
    write_model_artifact(models[[i]], v_usinas[i], args$artifact)
})
```

**Predict pipeline loop** (`/home/rogerio/git/mh-pfv/R/predict.r`, lines 62-82):

```r
apply_args <- list(v_usinas, processar_usina, ...)
if (parallel) {
    resultados <- do.call(future.apply::future_lapply,
        c(apply_args, list(future.seed = TRUE)))
} else {
    resultados <- do.call(lapply, apply_args)
}
```

**Provenance** (from E04-T002): `create_provenance()` creates a record with `plant_status` tracking. `write_provenance()` writes JSON to disk. The provenance file captures per-plant status, but there is no mechanism to read it back and filter plants on restart.

**Config structure** (`/home/rogerio/git/mh-pfv/R/config-file.r`): `config_names()` returns the list of required config keys. The config does not currently include a `resume` field.

### Design Decisions

1. **State file location**: The checkpoint state file is written to the output/artifact directory as `checkpoint-{run_id}.json`. On resume, the pipeline looks for any `checkpoint-*.json` file in the output directory.

2. **Resume detection**: Resume is triggered by an explicit `resume = TRUE` parameter on `train_main()` and `predict_main()`, NOT by automatic detection of state files. This prevents accidental resumes with stale state. The default is `resume = FALSE` (current behavior).

3. **Config hash validation**: On resume, the config hash in the checkpoint file must match the current config hash. If they differ, the resume is rejected with an error telling the operator the configuration changed.

4. **Parallel compatibility**: The checkpoint state is updated in the sequential post-processing phase (artifact writing for train, after result collection for predict), NOT inside parallel workers. This avoids thread-safety issues.

5. **Plant filtering**: On resume, completed plants are removed from `v_usinas` before the main processing loop. For predict, previously completed results must also be loaded (not recomputed).

6. **Train resume strategy**: For train, "resume" means skipping model fitting for completed plants and only fitting remaining plants. Previously saved artifacts remain on disk. The final artifact-writing loop only writes new artifacts.

7. **Predict resume strategy**: For predict, resume is more complex because the final output is a combined parquet file from all plants. Strategy: recompute only failed/pending plants, combine with previously saved per-plant intermediate results. This requires saving per-plant intermediate results to disk.

   **Simplification**: For this initial implementation, predict resume will only support resuming from per-plant processing. It will NOT support resuming the post-processing (organiza_resultados, write outputs). If the failure happens during post-processing, the full predict pipeline must be re-run. This keeps the implementation manageable.

## Specification

### Requirements

1. **Create checkpoint functions in `R/provenance.r`** (extend the file from E04-T002):
   - `write_checkpoint(provenance, output_dir)`: writes `checkpoint-{run_id}.json` to output_dir. Called after each plant completes (in the sequential phase).
   - `read_checkpoint(output_dir, config)`: reads the most recent `checkpoint-*.json` from output_dir. Returns the checkpoint provenance record if the config hash matches, or `NULL` if no valid checkpoint exists.
   - `get_pending_plants(checkpoint)`: returns the vector of plant IDs that are NOT "completed" in the checkpoint.

2. **Add `resume` parameter to `train_main()` and `predict_main()`**: Default `FALSE`. When `TRUE`, the pipeline checks for a valid checkpoint and skips completed plants.

3. **Train resume logic**: When `resume = TRUE`:
   - Call `read_checkpoint(args$artifact, args)` to find a valid checkpoint.
   - If found, filter `v_usinas` to only pending/failed plants.
   - Run the normal pipeline on filtered plants.
   - During artifact writing, only write artifacts for newly processed plants.
   - Create a new provenance record that merges completed plants from the checkpoint with newly completed plants.

4. **Predict resume logic**: When `resume = TRUE`:
   - Call `read_checkpoint(args$output, args)` to find a valid checkpoint.
   - If found, filter `v_usinas` to only pending/failed plants.
   - Run the normal pipeline on filtered plants.
   - For the output combination step, load per-plant intermediate results from disk for previously completed plants, combine with new results.
   - This requires saving per-plant intermediate results: add a `write_plant_result(result, id_usina, output_dir)` function that saves each plant's result as `plant-result-{id_usina}.rds` in the output directory.

5. **Checkpoint cleanup**: After a successful run (all plants completed), delete the checkpoint file from the output directory. Provenance JSON remains.

6. **Validation**: `read_checkpoint()` must validate the config hash matches. If the config hash does not match, log a warning and return `NULL` (treat as no valid checkpoint).

### Inputs/Props

- `write_checkpoint(provenance, output_dir)`: provenance list (from E04-T002), output directory path
- `read_checkpoint(output_dir, config)`: output directory path, current config list
- `get_pending_plants(checkpoint)`: checkpoint provenance list
- `write_plant_result(result, id_usina, output_dir)`: per-plant result list, plant ID, output directory
- `read_plant_result(id_usina, output_dir)`: plant ID, output directory

### Outputs/Behavior

- `write_checkpoint()`: writes JSON file, returns `invisible(filepath)`
- `read_checkpoint()`: returns provenance list or `NULL`
- `get_pending_plants()`: returns character vector of plant IDs
- `write_plant_result()`: saves RDS file, returns `invisible(filepath)`
- `read_plant_result()`: returns the per-plant result list

### Error Handling

- If the checkpoint file is corrupted (invalid JSON), `read_checkpoint()` logs a warning and returns `NULL` (clean start).
- If the config hash in the checkpoint does not match the current config, `read_checkpoint()` logs a warning with details and returns `NULL`.
- If a per-plant result file is missing or corrupted on resume, treat that plant as "pending" (reprocess it). Log a warning.
- `write_checkpoint()` and `write_plant_result()` use `tryCatch` to avoid crashing the pipeline on I/O failures.
- All messages in Portuguese.

## Acceptance Criteria

- [ ] Given `train_main(args, resume = FALSE)`, when executed, then the pipeline runs normally without checkpoint logic (backward compatible)
- [ ] Given `train_main(args, resume = TRUE)` with no existing checkpoint file, when executed, then the pipeline runs normally from scratch
- [ ] Given a train run that failed after completing 1 of 2 plants, when `train_main(args, resume = TRUE)` is called with the same config, then only the incomplete plant is reprocessed
- [ ] Given a train run that failed, when `train_main(args, resume = TRUE)` is called with a DIFFERENT config, then the pipeline runs from scratch (config hash mismatch) with a logged warning
- [ ] Given `predict_main(args, resume = TRUE)` with a valid checkpoint showing 1 of 2 plants completed, when executed, then only the pending plant is reprocessed and the final output combines results from both plants
- [ ] Given a fully successful train run, when the pipeline completes, then the checkpoint file is deleted from the artifact directory (only provenance JSON remains)
- [ ] Given a fully successful predict run, when the pipeline completes, then per-plant result files and the checkpoint file are cleaned up from the output directory
- [ ] Given `write_checkpoint()` is called after each plant completes, when the pipeline is interrupted, then the checkpoint file reflects the last successfully completed plant
- [ ] Given a corrupted checkpoint file (invalid JSON), when `read_checkpoint()` is called, then it returns `NULL` and logs a warning
- [ ] Given `predict_main(args, resume = TRUE)`, when a per-plant result file is missing, then that plant is reprocessed (treated as pending)

## Implementation Guide

### Suggested Approach

**Step 1: Add checkpoint functions to `R/provenance.r`**

```r
#' Escreve Checkpoint de Execucao
#'
#' Persiste o estado atual da execucao para permitir retomada.
#'
#' @param provenance lista de proveniencia
#' @param output_dir character, diretorio de saida
#'
#' @return caminho do arquivo (invisivelmente)
#'
#' @export
write_checkpoint <- function(provenance, output_dir) {
    lg <- lgr::get_logger("mhpfv")
    filename <- paste0("checkpoint-", provenance$run_id, ".json")
    filepath <- file.path(output_dir, filename)

    tryCatch({
        if (!dir.exists(output_dir)) {
            dir.create(output_dir, recursive = TRUE)
        }
        prov_json <- provenance
        prov_json$start_time <- format(
            provenance$start_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
        )
        json_str <- jsonlite::toJSON(prov_json, pretty = TRUE,
            auto_unbox = TRUE, null = "null")
        writeLines(json_str, filepath)
    }, error = function(e) {
        lg$warn("Falha ao escrever checkpoint: %s", conditionMessage(e))
    })

    invisible(filepath)
}

#' Le Checkpoint Valido do Diretorio
#'
#' Busca o checkpoint mais recente e valida o hash da configuracao.
#'
#' @param output_dir character, diretorio onde procurar checkpoints
#' @param config lista com a configuracao atual
#'
#' @return lista de proveniencia do checkpoint, ou NULL se nenhum valido
#'
#' @export
read_checkpoint <- function(output_dir, config) {
    lg <- lgr::get_logger("mhpfv")

    pattern <- "^checkpoint-.*\\.json$"
    files <- list.files(output_dir, pattern = pattern, full.names = TRUE)

    if (length(files) == 0L) return(NULL)

    # Usa o mais recente por data de modificacao
    newest <- files[which.max(file.mtime(files))]

    checkpoint <- tryCatch(
        jsonlite::fromJSON(newest, simplifyVector = FALSE),
        error = function(e) {
            lg$warn(
                "Checkpoint corrompido em '%s': %s",
                newest, conditionMessage(e)
            )
            return(NULL)
        }
    )

    if (is.null(checkpoint)) return(NULL)

    # Valida config hash
    current_hash <- digest::digest(
        normalize_config_for_hash(config),
        algo = "sha256"
    )
    if (!identical(checkpoint$config_hash, current_hash)) {
        lg$warn(
            "Checkpoint ignorado: hash da configuracao diferente (checkpoint: %s, atual: %s)",
            checkpoint$config_hash, current_hash
        )
        return(NULL)
    }

    lg$info("Checkpoint valido encontrado: %s", checkpoint$run_id)
    checkpoint
}

#' Retorna Usinas Pendentes de um Checkpoint
#'
#' @param checkpoint lista de proveniencia do checkpoint
#'
#' @return character vector de IDs de usinas pendentes
#'
#' @export
get_pending_plants <- function(checkpoint) {
    statuses <- checkpoint$plant_status
    pending <- vapply(statuses, function(s) s != "completed", logical(1L))
    names(statuses)[pending]
}

#' Salva Resultado Intermediario de Uma Usina
#'
#' @param result lista com resultado da usina (com_cortes, sem_cortes)
#' @param id_usina character, identificador da usina
#' @param output_dir character, diretorio de saida
#'
#' @return caminho do arquivo (invisivelmente)
write_plant_result <- function(result, id_usina, output_dir) {
    filepath <- file.path(output_dir, paste0("plant-result-", id_usina, ".rds"))
    tryCatch(
        saveRDS(result, filepath),
        error = function(e) {
            lg <- lgr::get_logger("mhpfv")
            lg$warn(
                "Falha ao salvar resultado da usina '%s': %s",
                id_usina, conditionMessage(e)
            )
        }
    )
    invisible(filepath)
}

#' Le Resultado Intermediario de Uma Usina
#'
#' @param id_usina character, identificador da usina
#' @param output_dir character, diretorio de saida
#'
#' @return lista com resultado ou NULL se nao encontrado/corrompido
read_plant_result <- function(id_usina, output_dir) {
    filepath <- file.path(output_dir, paste0("plant-result-", id_usina, ".rds"))
    if (!file.exists(filepath)) return(NULL)
    tryCatch(
        readRDS(filepath),
        error = function(e) {
            lg <- lgr::get_logger("mhpfv")
            lg$warn(
                "Resultado intermediario corrompido para usina '%s': %s",
                id_usina, conditionMessage(e)
            )
            return(NULL)
        }
    )
}

#' Remove Arquivos de Checkpoint e Resultados Intermediarios
#'
#' @param output_dir character, diretorio de saida
#' @param run_id character, ID da execucao (opcional, limpa todos se NULL)
#'
#' @return invisible(NULL)
cleanup_checkpoint <- function(output_dir, run_id = NULL) {
    lg <- lgr::get_logger("mhpfv")

    # Remove checkpoint files
    if (!is.null(run_id)) {
        cp_pattern <- paste0("^checkpoint-", run_id, "\\.json$")
    } else {
        cp_pattern <- "^checkpoint-.*\\.json$"
    }
    cp_files <- list.files(output_dir, pattern = cp_pattern, full.names = TRUE)

    # Remove per-plant result files
    pr_files <- list.files(output_dir, pattern = "^plant-result-.*\\.rds$",
        full.names = TRUE)

    all_files <- c(cp_files, pr_files)
    if (length(all_files) > 0L) {
        file.remove(all_files)
        lg$debug("Removidos %d arquivos de checkpoint/intermediarios",
            length(all_files))
    }

    invisible(NULL)
}
```

**Step 2: Modify `train_main()` to support resume**

In `/home/rogerio/git/mh-pfv/R/train.r`:

```r
train_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE, resume = FALSE) {

    provenance <- create_provenance(args, "train", parallel)
    checkpoint <- NULL
    completed_plants <- character(0L)

    if (resume) {
        checkpoint <- read_checkpoint(args$artifact, args)
        if (!is.null(checkpoint)) {
            completed_plants <- setdiff(
                args$ids_usinas,
                get_pending_plants(checkpoint)
            )
            # Carry over completed plant statuses
            for (iu in completed_plants) {
                provenance <- update_plant_status(provenance, iu, "completed")
            }
        }
    }

    on.exit({
        if (provenance$status == "running") {
            provenance <- finalize_provenance(provenance, "failed")
        }
        write_provenance(provenance, args$artifact)
    }, add = TRUE)

    # Filter to pending plants
    v_usinas_pending <- setdiff(args$ids_usinas, completed_plants)

    if (length(v_usinas_pending) == 0L) {
        provenance <- finalize_provenance(provenance, "completed")
        cleanup_checkpoint(args$artifact)
        return(invisible(NULL))
    }

    v_usinas <- v_usinas_pending
    # ... rest of pipeline with v_usinas ...

    # After processing, update statuses and write checkpoint after each plant
    lapply(seq_along(v_usinas), function(i) {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
        provenance <<- update_plant_status(provenance, v_usinas[i], "completed")
        write_checkpoint(provenance, args$artifact)
    })

    provenance <- finalize_provenance(provenance, "completed")
    cleanup_checkpoint(args$artifact)
}
```

**Step 3: Modify `predict_main()` to support resume**

In `/home/rogerio/git/mh-pfv/R/predict.r`, the approach is similar but also saves/loads per-plant intermediate results:

```r
predict_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE, resume = FALSE) {

    provenance <- create_provenance(args, "predict", parallel)
    checkpoint <- NULL
    completed_plants <- character(0L)

    if (resume) {
        checkpoint <- read_checkpoint(args$output, args)
        if (!is.null(checkpoint)) {
            # Only count plants as completed if their result file exists
            candidate_completed <- setdiff(
                args$ids_usinas,
                get_pending_plants(checkpoint)
            )
            completed_plants <- Filter(function(iu) {
                !is.null(read_plant_result(iu, args$output))
            }, candidate_completed)
            for (iu in completed_plants) {
                provenance <- update_plant_status(provenance, iu, "completed")
            }
        }
    }

    # ... set up on.exit, data loading, NWP association ...

    v_usinas_pending <- setdiff(args$ids_usinas, completed_plants)

    if (length(v_usinas_pending) > 0L) {
        # Process pending plants (same apply_args pattern)
        # ...
        resultados_new <- do.call(lapply_fn, apply_args_pending)

        # Save per-plant results and update checkpoint
        for (i in seq_along(v_usinas_pending)) {
            write_plant_result(
                resultados_new[[i]], v_usinas_pending[i], args$output
            )
            provenance <- update_plant_status(
                provenance, v_usinas_pending[i], "completed"
            )
            write_checkpoint(provenance, args$output)
        }
    }

    # Combine all results: load completed from disk, merge with new
    all_resultados <- lapply(args$ids_usinas, function(iu) {
        if (iu %in% v_usinas_pending) {
            idx <- match(iu, v_usinas_pending)
            resultados_new[[idx]]
        } else {
            read_plant_result(iu, args$output)
        }
    })

    # Continue with organiza_resultados using v_usinas = args$ids_usinas
    resultados_organizados <- organiza_resultados(
        resultados = all_resultados,
        v_usinas = args$ids_usinas
    )

    # ... write outputs ...

    provenance <- finalize_provenance(provenance, "completed")
    cleanup_checkpoint(args$output)
}
```

### Key Files to Modify

| File                                                             | Change                                                                                 |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `/home/rogerio/git/mh-pfv/R/provenance.r`                        | Add checkpoint, plant result, and cleanup functions                                    |
| `/home/rogerio/git/mh-pfv/R/train.r`                             | Add `resume` parameter, checkpoint read/filter/write logic                             |
| `/home/rogerio/git/mh-pfv/R/predict.r`                           | Add `resume` parameter, checkpoint read/filter/write logic, per-plant result save/load |
| `/home/rogerio/git/mh-pfv/tests/testthat/test-provenance.r`      | Add checkpoint-related tests (extend from E04-T002)                                    |
| `/home/rogerio/git/mh-pfv/tests/testthat/test-pipeline-resume.r` | **NEW FILE** -- integration tests for resume behavior                                  |
| `/home/rogerio/git/mh-pfv/NAMESPACE`                             | Regenerated by `devtools::document()`                                                  |

### Patterns to Follow

- **`on.exit()` stacking**: Follow the existing pattern in `train_main()` -- `add = TRUE` on all `on.exit()` calls. Provenance on.exit must be registered before parallel plan on.exit.
- **`provenance <<-` pattern**: Same as E04-T002 -- use `<<-` in `lapply` callbacks to update provenance in enclosing scope.
- **Error wrapping with `tryCatch`**: Follow `write_provenance()` from E04-T002 -- all I/O operations that could fail must be wrapped.
- **Test data**: Use `withr::local_tempdir()` for checkpoint directories, `gen_config()` and `gen_model_artifact()` for test data.
- **Portuguese messages**: All log messages and errors in Portuguese.

### Pitfalls to Avoid

- **Do NOT modify parallel worker functions**: Checkpoint writing happens in the sequential phase only. Do not try to write checkpoints from inside `future_lapply` workers -- this would create race conditions.
- **`setdiff()` for plant filtering**: Use `setdiff(args$ids_usinas, completed_plants)` to get pending plants. This preserves the original ordering of `v_usinas`.
- **Per-plant results in predict**: The `processar_usina()` return value is `list(com_cortes = <dt>, sem_cortes = <dt>)`. These data.tables can be large. Use RDS format (not JSON) for intermediate results to preserve data.table structure and avoid serialization overhead.
- **Cleanup timing**: Delete checkpoint and intermediate files ONLY after the entire pipeline succeeds. If cleanup fails, log a warning but do not error.
- **`read_checkpoint()` must handle `jsonlite::fromJSON` list flattening**: `jsonlite::fromJSON` with `simplifyVector = FALSE` is needed to preserve the `plant_status` as a named list of scalars, not a character vector.
- **Predict resume with parallel**: When resuming predict in parallel mode, only pending plants are dispatched to workers. The `apply_args` must be constructed with `v_usinas_pending` instead of the full `v_usinas`.
- **Do NOT add `resume` to CLI/config yet**: The `resume` parameter is on `train_main()`/`predict_main()` only. Wiring it to the CLI parser is deferred to Epic 05 (the `--parallel` and `--resume` CLI flags belong there).

## Testing Requirements

### Unit Tests

Add to `/home/rogerio/git/mh-pfv/tests/testthat/test-provenance.r`:

1. **`write_checkpoint` creates file**: Write checkpoint to `withr::local_tempdir()`, verify file exists.
2. **`read_checkpoint` reads valid checkpoint**: Write then read, verify all fields match.
3. **`read_checkpoint` returns NULL for empty dir**: Verify NULL on dir with no checkpoint files.
4. **`read_checkpoint` returns NULL for config mismatch**: Write checkpoint with config A, read with config B, verify NULL.
5. **`read_checkpoint` returns NULL for corrupted file**: Write invalid JSON to checkpoint path, verify NULL and warning.
6. **`get_pending_plants` filters correctly**: Given a checkpoint with some plants "completed" and others "pending"/"failed", verify only non-completed plants are returned.
7. **`write_plant_result` / `read_plant_result` roundtrip**: Save and load a per-plant result, verify identical.
8. **`read_plant_result` returns NULL for missing file**: Verify NULL when file does not exist.
9. **`cleanup_checkpoint` removes files**: Create checkpoint and plant-result files, call cleanup, verify all removed.
10. **`cleanup_checkpoint` is silent on empty dir**: Call on dir with no checkpoint files, verify no error.

### Integration Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-pipeline-resume.r`:

1. **Train resume skips completed plants**: Run `train_main()` for 2 plants. Manually create a checkpoint marking 1 plant as completed. Run `train_main(resume = TRUE)`. Verify only 1 artifact is (re)written.
2. **Train resume with config mismatch runs from scratch**: Create a checkpoint with different config hash. Run `train_main(resume = TRUE)`. Verify all plants are processed.
3. **Predict resume combines old and new results**: Save a per-plant result file for 1 plant. Create a checkpoint marking that plant as completed. Run `predict_main(resume = TRUE)`. Verify the output parquet contains data from both plants.
4. **Successful run cleans up checkpoint files**: Run `train_main(resume = FALSE)` to completion. Verify no checkpoint files remain in artifact directory (only provenance JSON).

## Dependencies

- **Blocked By**: E04-T002 (provenance infrastructure, `normalize_config_for_hash()`, `write_provenance()`)
- **Blocks**: None

## Effort Estimate

**Points**: 5
**Confidence**: High
