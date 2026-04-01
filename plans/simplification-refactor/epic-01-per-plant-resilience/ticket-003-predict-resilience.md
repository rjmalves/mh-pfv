# E01-T003: Predict Pipeline Resilience

## Objective

Apply the same `tryCatch` + `plant_error` sentinel pattern to the predict pipeline (`predict_main` in `R/predict.r`). On error from `processar_usina`, return a `plant_error` sentinel. The post-processing loop branches on `is_plant_error()`: failed plants get `update_plant_status(..., "failed")` and are excluded from result assembly; successful plants are processed normally.

## Dependencies

- E01-T001 (plant_error sentinel)

## Files to Create/Modify

| File          | Action | Details                                                                                                                                                                                    |
| ------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `R/predict.r` | Modify | Wrap `processar_usina` in `tryCatch` in serial and parallel paths; rewrite post-processing with success/failure branching; handle failed plants in result assembly; compute `final_status` |

## Technical Details

### Serial path (lines ~120-128 currently)

```r
resultados_new <- lapply(v_usinas_pending, function(iu) {
    t0 <- proc.time()[["elapsed"]]
    result <- tryCatch(
        do.call(processar_usina, c(list(iu), extra_args)),
        error = function(e) {
            lg$error("Falha no processamento da usina %s: %s", iu, conditionMessage(e))
            plant_error(iu, e)
        }
    )
    metrics <<- record_plant_timing(
        metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L)
    )
    result
})
```

### Parallel path (lines ~107-116 currently)

```r
resultados_new <- do.call(future.apply::future_lapply,
    c(list(v_usinas_pending, function(iu) {
        tryCatch(
            do.call(processar_usina,
                c(list(iu), extra_args_for_parallel)),
            error = function(e) plant_error(iu, e)
        )
    }), list(future.seed = TRUE)))
```

Note: the parallel path currently uses a different call structure (`apply_args` passed to `future_lapply`). The `tryCatch` must wrap the body of the anonymous function that calls `processar_usina`. Study the exact current call structure to determine the right insertion point -- the `apply_args` list is unpacked as named arguments to `future_lapply`.

### Post-processing loop (lines ~131-152 currently)

Replace the `for` loop with branching:

```r
n_failed <- 0L
n_total <- length(v_usinas_pending)
for (i in seq_along(v_usinas_pending)) {
    iu <- v_usinas_pending[i]
    if (is_plant_error(resultados_new[[i]])) {
        update_plant_status(provenance, iu, "failed")
        n_failed <- n_failed + 1L
        lg$error("Usina %s falhou: %s", iu, resultados_new[[i]]$error)
    } else {
        result <- resultados_new[[i]]
        n_rows <- nrow(result$com_cortes)
        n_na <- sum(is.na(result$com_cortes$valor))
        n_total_vals <- length(result$com_cortes$valor)
        metrics <- record_plant_data_volume(
            metrics, iu, as.numeric(n_rows), as.numeric(n_na),
            as.numeric(n_total_vals)
        )
        provenance <<- update_plant_status(provenance, iu, "completed")
        if (resume) {
            write_plant_result(result, iu, args$output)
            write_checkpoint(provenance, args$output)
        }
    }
    lg$info("Usina %s processada (%d/%d)", iu, i, n_total)
}
```

### Result assembly (lines ~155-161 currently)

Failed plants must be excluded from result assembly. When assembling the final `resultados` list, skip `plant_error` entries:

```r
resultados <- lapply(args$ids_usinas, function(iu) {
    if (iu %in% v_usinas_pending) {
        idx <- match(iu, v_usinas_pending)
        r <- resultados_new[[idx]]
        if (is_plant_error(r)) return(NULL)
        r
    } else {
        read_plant_result(iu, args$output)
    }
})
```

Then filter NULLs before `organiza_resultados`:

```r
valid_idx <- !vapply(resultados, is.null, logical(1L))
resultados_valid <- resultados[valid_idx]
usinas_valid <- args$ids_usinas[valid_idx]
```

If `length(resultados_valid) == 0L`, skip the output writing entirely and finalize with `"failed"`.

### Compute final status

```r
final_status <- if (n_failed == 0L) "completed" else "failed"
provenance <- finalize_provenance(provenance, final_status)
```

Remove the unconditional `finalize_provenance(provenance, "completed")` at the end.

## Acceptance Criteria

- [ ] Serial predict: if 1 of N plants throws, the remaining N-1 are still processed
- [ ] Parallel predict: same behavior
- [ ] Failed plants have `plant_status == "failed"` in provenance
- [ ] Successful plants have `plant_status == "completed"` in provenance
- [ ] Failed plants are excluded from result assembly (no crash in `organiza_resultados`)
- [ ] If all plants fail, output files are not written, status is `"failed"`
- [ ] Timing is recorded for all plants (including failed ones)
- [ ] `devtools::check()` passes

## Definition of Done

- `R/predict.r` modified with `tryCatch` in both paths and branching post-processing
- Result assembly handles missing plants gracefully
- Existing tests pass (no regressions)
- `devtools::check()` produces no new warnings

## Estimated Effort

~25 minutes
