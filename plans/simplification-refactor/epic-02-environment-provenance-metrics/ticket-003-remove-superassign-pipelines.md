# E02-T003: Remove <<- from Pipelines

## Objective

With provenance and metrics now using environments (reference semantics), remove all `<<-` assignments for `provenance` and `metrics` from `train.r` and `predict.r`. Also update `health-report.r` if needed to read from environment instead of list.

## Dependencies

- E02-T001 (provenance as environment)
- E02-T002 (metrics as environment)

## Files to Create/Modify

| File                | Action | Details                                                                                                                                            |
| ------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `R/train.r`         | Modify | Remove `provenance <<-` and `metrics <<-` from all `lapply` bodies; adjust `finalize_provenance`/`finalize_metrics` calls (no reassignment needed) |
| `R/predict.r`       | Modify | Same: remove `provenance <<-` and `metrics <<-` from all loops; adjust finalization calls                                                          |
| `R/health-report.r` | Modify | Update `build_plant_reports` to convert `plant_status` environment to list before iteration if needed                                              |

## Technical Details

### `train.r` changes

**Serial path (`lapply` body, currently ~line 117-134):**

Before (from Epic 01):

```r
metrics <<- record_plant_timing(metrics, iu, ...)
```

After:

```r
record_plant_timing(metrics, iu, ...)
```

The return value is no longer needed -- `metrics` is an environment mutated in place.

**Post-processing loop (currently ~line 138-151):**

Before (from Epic 01):

```r
provenance <<- update_plant_status(provenance, v_usinas[i], "completed")
metrics <<- record_model_quality(metrics, v_usinas[i], models[[i]]$metadata)
```

After:

```r
update_plant_status(provenance, v_usinas[i], "completed")
record_model_quality(metrics, v_usinas[i], models[[i]]$metadata)
```

**Parallel path timing (currently ~line 113-115):**

Before:

```r
metrics <- record_plant_timing(metrics, iu, est_per_plant)
```

This is a regular `<-` (not `<<-`) in a `for` loop, but with environments it becomes:

```r
record_plant_timing(metrics, iu, est_per_plant)
```

**Finalization (end of `train_main`):**

Before:

```r
provenance <- finalize_provenance(provenance, final_status)
metrics <- finalize_metrics(metrics)
```

After:

```r
finalize_provenance(provenance, final_status)
finalize_metrics(metrics)
```

Same in `on.exit` handler:

```r
# Before
provenance <- finalize_provenance(provenance, "failed")
metrics <- finalize_metrics(metrics)

# After
finalize_provenance(provenance, "failed")
finalize_metrics(metrics)
```

### `predict.r` changes

Same pattern as train. Specific locations:

1. Serial `lapply` body: `metrics <<-` becomes plain call
2. Post-processing `for` loop: `provenance <<-` and `metrics <-` become plain calls
3. Parallel path timing: `metrics <-` becomes plain call
4. `on.exit` handler: remove reassignment
5. Final finalization: remove reassignment

**`load_predict_resume_state`:**

Currently does `provenance <- update_plant_status(provenance, iu, "completed")`. With environments, this is harmless (reassigning same reference), but can be simplified to just `update_plant_status(provenance, iu, "completed")`.

Same for `load_train_resume_state` in `train.r`.

### `health-report.r` changes

`build_plant_reports` iterates `provenance$plant_ids` (a character vector) and accesses `provenance$plant_status[[iu]]`. With environments, `$` and `[[` access works the same. However, if any code does `names(provenance$plant_status)` or iterates it with `vapply`, that won't work on environments. Check this.

Looking at the current code: `provenance$plant_status[[iu]]` -- this works on environments. No iteration over `plant_status` happens in `build_plant_reports`. **No change needed.**

But `build_health_report` calls `finalize_metrics` in `on.exit` which now returns `invisible(metrics)`. The `on.exit` block assigns `metrics <- finalize_metrics(metrics)` -- this should just become `finalize_metrics(metrics)`. This is in `train.r` and `predict.r`, not in `health-report.r` itself.

### `n_failed <<-` in post-processing

The `n_failed <<- n_failed + 1L` from Epic 01 uses `<<-` inside a `lapply` closure. This is a local counter, not provenance/metrics. Options:

1. Keep `<<-` for `n_failed` (it is a simple counter in a factory-function-like pattern)
2. Convert the `lapply` to a `for` loop to avoid `<<-` entirely

The proposal says the `for` loop approach is cleaner. Convert the post-processing `lapply` to a `for` loop in both `train.r` and `predict.r` to eliminate all `<<-`.

## Acceptance Criteria

- [ ] Zero `<<-` in `R/train.r` (verified by grep)
- [ ] Zero `<<-` in `R/predict.r` (verified by grep)
- [ ] `on.exit` handlers work correctly (provenance and metrics are mutated before handler runs)
- [ ] `devtools::test()` passes
- [ ] `devtools::check()` passes

## Definition of Done

- All `<<-` removed from `train.r` and `predict.r`
- Post-processing converted to `for` loops where applicable
- `devtools::check()` passes

## Estimated Effort

~20 minutes
