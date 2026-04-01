# E02-T002: Metrics as Environment

## Objective

Rewrite `create_metrics`, `record_plant_timing`, `record_plant_data_volume`, `record_model_quality`, `finalize_metrics`, and `write_metrics` to use R environments instead of lists. Mutations become in-place, eliminating the need for `<<-` or return-and-reassign patterns.

## Dependencies

- E02-T001 (provenance as environment -- establishes the pattern)

## Files to Create/Modify

| File          | Action | Details                                                                              |
| ------------- | ------ | ------------------------------------------------------------------------------------ |
| `R/metrics.r` | Modify | Rewrite all functions to use environments; add `metrics_as_list()` for serialization |

## Technical Details

### `create_metrics` -- return environment

```r
create_metrics <- function(run_id, mode) {
    stopifnot(
        is.character(run_id), length(run_id) == 1L,
        is.character(mode), length(mode) == 1L
    )
    m <- new.env(parent = emptyenv())
    m$run_id <- run_id
    m$mode <- mode
    m$created_at <- NULL
    m$pipeline <- list()
    m$plants <- new.env(parent = emptyenv())
    m
}
```

`plants` is an environment for O(1) per-plant access.

### `record_plant_timing` -- mutate in place

```r
record_plant_timing <- function(metrics, id_usina, duration_secs) {
    stopifnot(
        is.environment(metrics),
        is.character(id_usina), length(id_usina) == 1L,
        is.numeric(duration_secs), length(duration_secs) == 1L
    )
    if (is.null(metrics$plants[[id_usina]])) {
        metrics$plants[[id_usina]] <- list()
    }
    metrics$plants[[id_usina]]$duration_seconds <- duration_secs
    invisible(metrics)
}
```

### `record_plant_data_volume` -- mutate in place

Same pattern: validate `is.environment(metrics)`, mutate `metrics$plants[[id_usina]]$data_volume`.

### `record_model_quality` -- mutate in place

Same pattern: validate `is.environment(metrics)`, mutate `metrics$plants[[id_usina]]$model_quality`.

### `finalize_metrics` -- mutate in place

```r
finalize_metrics <- function(metrics) {
    stopifnot(is.environment(metrics))

    plant_list <- as.list(metrics$plants)
    durations <- vapply(
        plant_list,
        function(p) {
            if (!is.null(p$duration_seconds)) p$duration_seconds else NA_real_
        },
        numeric(1L)
    )
    valid_durations <- durations[!is.na(durations)]
    n_completed <- length(valid_durations)

    metrics$created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    metrics$pipeline <- list(
        n_plants = length(plant_list),
        n_plants_completed = n_completed,
        mean_plant_duration_seconds = if (n_completed > 0L)
            round(mean(valid_durations), 2L) else NA_real_,
        max_plant_duration_seconds = if (n_completed > 0L)
            round(max(valid_durations), 2L) else NA_real_,
        min_plant_duration_seconds = if (n_completed > 0L)
            round(min(valid_durations), 2L) else NA_real_
    )
    invisible(metrics)
}
```

Key difference: `as.list(metrics$plants)` to iterate over the plants environment.

### `metrics_as_list` -- serialization helper

```r
metrics_as_list <- function(metrics) {
    out <- as.list(metrics)
    out$plants <- as.list(metrics$plants)
    out
}
```

### `write_metrics` -- use `metrics_as_list`

Replace `jsonlite::toJSON(metrics, ...)` with `jsonlite::toJSON(metrics_as_list(metrics), ...)`.

## Acceptance Criteria

- [ ] `create_metrics()` returns an environment with `is.environment()` TRUE
- [ ] `record_plant_timing()` mutates in place (no return reassignment needed)
- [ ] `record_plant_data_volume()` mutates in place
- [ ] `record_model_quality()` mutates in place
- [ ] `finalize_metrics()` mutates in place
- [ ] `write_metrics()` produces identical JSON format to before
- [ ] `devtools::check()` passes

## Definition of Done

- All metrics functions in `R/metrics.r` updated to use environments
- `metrics_as_list()` added
- `write_metrics` calls `metrics_as_list()` before serialization
- `devtools::check()` passes

## Estimated Effort

~20 minutes
