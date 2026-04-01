# E02-T001: Provenance as Environment

## Objective

Rewrite `create_provenance`, `update_plant_status`, `finalize_provenance` to use an R environment instead of a list. Add `prov_as_list()` conversion for serialization. Update `write_provenance`, `write_checkpoint`, and `format_provenance_timestamps` to handle environments.

## Dependencies

- E01-T004 (resilience tests complete -- ensures the codebase is stable before this refactor)

## Files to Create/Modify

| File             | Action | Details                                                                                                                                                                        |
| ---------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `R/provenance.r` | Modify | Rewrite `create_provenance`, `update_plant_status`, `finalize_provenance`; add `prov_as_list()`; update `write_provenance`, `write_checkpoint`, `format_provenance_timestamps` |

## Technical Details

### `create_provenance` -- return environment

```r
create_provenance <- function(config, mode, parallel = FALSE) {
    run_id <- generate_run_id(mode)
    plant_ids <- config$ids_usinas

    prov <- new.env(parent = emptyenv())
    prov$run_id <- run_id
    prov$mode <- mode
    prov$package_version <- as.character(utils::packageVersion("mhpfv"))
    prov$r_version <- paste0(R.version$major, ".", R.version$minor)
    prov$start_time <- Sys.time()
    prov$end_time <- NULL
    prov$duration_seconds <- NULL
    prov$config_hash <- digest::digest(
        normalize_config_for_hash(config), algo = "sha256"
    )
    prov$n_plants <- length(plant_ids)
    prov$plant_ids <- plant_ids
    prov$plant_status <- new.env(parent = emptyenv())
    for (iu in plant_ids) prov$plant_status[[iu]] <- "pending"
    prov$parallel <- parallel
    prov$status <- "running"

    prov
}
```

Key change: `plant_status` is also an environment for O(1) per-plant mutation.

### `update_plant_status` -- mutate in place

```r
update_plant_status <- function(provenance, id_usina, status) {
    valid_status <- c("completed", "failed", "skipped")
    stopifnot(
        is.environment(provenance),
        is.character(id_usina), length(id_usina) == 1L,
        status %in% valid_status
    )
    provenance$plant_status[[id_usina]] <- status
    invisible(provenance)
}
```

Returns `invisible(provenance)` instead of `provenance` (caller does not need the return value since the environment is mutated in place). Existing callers that do `provenance <- update_plant_status(...)` will still work -- reassigning the same environment reference is a no-op.

### `finalize_provenance` -- mutate in place

```r
finalize_provenance <- function(provenance, status = "completed") {
    stopifnot(
        is.environment(provenance),
        status %in% c("completed", "failed")
    )
    provenance$end_time <- Sys.time()
    provenance$duration_seconds <- as.numeric(
        difftime(provenance$end_time, provenance$start_time, units = "secs")
    )
    provenance$status <- status
    invisible(provenance)
}
```

### `prov_as_list` -- serialization helper

```r
prov_as_list <- function(provenance) {
    out <- as.list(provenance)
    out$plant_status <- as.list(provenance$plant_status)
    out
}
```

### `write_provenance` -- use `prov_as_list`

In the `tryCatch` block, replace:

```r
prov_json <- format_provenance_timestamps(provenance)
```

with:

```r
prov_json <- format_provenance_timestamps(prov_as_list(provenance))
```

### `write_checkpoint` -- use `prov_as_list`

Same change: `prov_json <- format_provenance_timestamps(prov_as_list(provenance))`

### `format_provenance_timestamps` -- no change needed

This function operates on list fields (`$start_time`, `$end_time`), which work the same on both lists and the output of `prov_as_list()`.

### `load_train_resume_state` and `load_predict_resume_state`

These functions call `update_plant_status(provenance, iu, "completed")` and currently reassign the result. With environments, the reassignment is harmless (same reference). The `provenance <- state$provenance` in the caller also works. No change needed in the resume functions themselves.

### `read_checkpoint` -- no change needed

Checkpoints are read from JSON as lists (not environments). `get_pending_plants` operates on lists. No change needed.

### `build_plant_reports` in `health-report.r`

This function reads `provenance$plant_status[[iu]]`. With an environment, `[[` access works the same way. However, if `provenance` is an environment, iteration via `provenance$plant_ids` still works. **No change needed** in `health-report.r`.

## Acceptance Criteria

- [ ] `create_provenance()` returns an environment with `is.environment()` TRUE
- [ ] `update_plant_status()` mutates in place (same object, verified by `identical()` on the environment)
- [ ] `finalize_provenance()` mutates in place
- [ ] `prov_as_list()` converts to a plain list with `plant_status` also as a list
- [ ] `write_provenance()` produces identical JSON format to before
- [ ] `write_checkpoint()` produces identical JSON format to before
- [ ] `read_checkpoint()` still works (reads list from JSON, not environment)
- [ ] `devtools::check()` passes

## Definition of Done

- All provenance functions in `R/provenance.r` updated
- `prov_as_list()` added
- `write_provenance` and `write_checkpoint` call `prov_as_list()` before serialization
- `devtools::check()` passes

## Estimated Effort

~20 minutes
