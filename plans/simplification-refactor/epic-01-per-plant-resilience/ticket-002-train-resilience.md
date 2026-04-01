# E01-T002: Train Pipeline Resilience

## Objective

Wrap `ajustar_usina` calls in `tryCatch` within both serial (`lapply`) and parallel (`future_lapply`) paths of `train_main`. On error, return a `plant_error` sentinel instead of propagating the exception. Modify the post-processing loop to branch on `is_plant_error()`: failed plants get `update_plant_status(..., "failed")` and no artifact write; successful plants proceed as before. Compute `final_status` based on failure count.

## Dependencies

- E01-T001 (plant_error sentinel)

## Files to Create/Modify

| File        | Action | Details                                                                                                                                              |
| ----------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `R/train.r` | Modify | Wrap `ajustar_usina` in `tryCatch` in serial and parallel paths; rewrite post-processing loop with success/failure branching; compute `final_status` |

## Technical Details

### Serial path (lines ~117-134 currently)

Replace the `lapply` body with:

```r
models <- lapply(v_usinas, function(iu) {
    t0 <- proc.time()[["elapsed"]]
    result <- tryCatch(
        ajustar_usina(iu,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            config = args
        ),
        error = function(e) {
            lg$error("Falha no ajuste da usina %s: %s", iu, conditionMessage(e))
            plant_error(iu, e)
        }
    )
    metrics <<- record_plant_timing(
        metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L)
    )
    result
})
```

Note: the `metrics <<-` stays for now (will be removed in Epic 02). The `tryCatch` is the only change in the serial inner loop.

### Parallel path (lines ~100-115 currently)

```r
models <- future.apply::future_lapply(v_usinas, function(iu) {
    tryCatch(
        ajustar_usina(iu,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            config = args
        ),
        error = function(e) plant_error(iu, e)
    )
}, future.seed = TRUE)
```

Logging inside the parallel worker is unreliable (`multisession`), so errors are logged in the post-processing loop.

### Post-processing loop (lines ~138-151 currently)

Replace with:

```r
n_failed <- 0L
n_total <- length(v_usinas)
lapply(seq_along(v_usinas), function(i) {
    if (is_plant_error(models[[i]])) {
        update_plant_status(provenance, v_usinas[i], "failed")
        n_failed <<- n_failed + 1L
        lg$error("Usina %s falhou: %s", v_usinas[i], models[[i]]$error)
    } else {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
        provenance <<- update_plant_status(
            provenance, v_usinas[i], "completed"
        )
        if ("metadata" %in% names(models[[i]])) {
            metrics <<- record_model_quality(
                metrics, v_usinas[i], models[[i]]$metadata
            )
        }
    }
    if (resume) write_checkpoint(provenance, args$artifact)
    lg$info("Usina %s processada (%d/%d)", v_usinas[i], i, n_total)
})

final_status <- if (n_failed == 0L) "completed" else "failed"
provenance <- finalize_provenance(provenance, final_status)
```

Note: `provenance <<-` and `metrics <<-` stay for now (removed in Epic 02). The `n_failed <<-` also uses `<<-` but is local to this function and acceptable.

### Replace final `finalize_provenance` call

The current unconditional `finalize_provenance(provenance, "completed")` at the end of `train_main` must be removed, since the post-processing loop now determines the final status.

## Acceptance Criteria

- [ ] Serial train: if 1 of N plants throws, the remaining N-1 still produce artifacts
- [ ] Parallel train: same behavior via `future_lapply`
- [ ] Failed plants have `plant_status == "failed"` in provenance
- [ ] Successful plants have `plant_status == "completed"` in provenance
- [ ] `final_status` is `"completed"` only when `n_failed == 0L`
- [ ] Error message from failed plant is logged via `lg$error`
- [ ] Timing is recorded for all plants (including failed ones)
- [ ] `devtools::check()` passes

## Definition of Done

- `R/train.r` modified with `tryCatch` in both paths and branching post-processing
- Existing tests pass (no regressions)
- `devtools::check()` produces no new warnings

## Estimated Effort

~20 minutes
