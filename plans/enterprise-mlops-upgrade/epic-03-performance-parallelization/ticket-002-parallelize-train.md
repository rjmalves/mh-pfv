# E03-T002 Parallelize train_main Per-Plant Processing

## Context

### Background

The `train_main()` function in `R/train.r` processes each plant sequentially via `lapply(v_usinas, ajustar_usina, ...)` at line 52. Each call to `ajustar_usina()` is independent -- it filters shared data.tables by `id_usina`, fits a model, and returns a `list(id_usina, parametros)`. The strategy object is a simple S3 list (safe to serialize). This makes `lapply` a direct candidate for replacement with `future_lapply`.

However, there is a critical inefficiency: inside `ajustar_usina()`, the call `associa_nwp_usina(dt_usinas, dt_irrad_prev)` at line 75 computes the Haversine NWP-to-plant association for ALL plants, then filters to the current plant. This redundant work is done N times in the loop. Before parallelizing, this call must be hoisted out of the per-plant function so the association is computed once and shared across all workers.

### Relation to Epic

This is the first pipeline parallelization ticket (after E03-T001 infrastructure). It establishes the pattern for `future_lapply` integration that E03-T003 will replicate for `predict_main`. The hoisting of `associa_nwp_usina` here sets the architectural precedent for the same change in E03-T003.

### Current State

`R/train.r` contains:

```r
train_main <- function(args, strategy = linear_regression_strategy()) {
    conn <- conectamock_pfv(args$input)
    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)
    dataset <- get_dataset(args, conn)

    models <- lapply(v_usinas, ajustar_usina,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_irrad_prev = dataset$irrad_prev,
        dt_corte_obs = dataset$corte,
        fonte = args$ordem_prioridade_fontes,
        fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
        strategy = strategy
    )

    lapply(seq_along(v_usinas), function(i) {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
    })
}
```

Inside `ajustar_usina()`, line 75:

```r
dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dt_irrad_prev)
```

This is called once per plant but computes associations for ALL plants. The result is then filtered at line 77: `irrad_prev <- dt_irrad_prev_filt_n[id_usina == iu & passo_prev == "D+0"]`.

The `R/parallel.r` module from E03-T001 provides `setup_parallel_plan()` and `reset_parallel_plan()`.

## Specification

### Requirements

1. **Hoist `associa_nwp_usina()`** out of `ajustar_usina()` and into `train_main()`, so it is called once before the loop. Pass the pre-computed `dt_irrad_prev_filt` (after `associa_nwp_usina` and `adicionar_passo_previsao`) to `ajustar_usina()` instead of the raw `dt_irrad_prev`.

2. **Add `parallel` parameter** to `train_main()` signature: `train_main(args, strategy = linear_regression_strategy(), parallel = FALSE)`. When `FALSE`, use standard `lapply` (backward compatible). When `TRUE`, set up a parallel plan, use `future_lapply`, and tear down the plan.

3. **Replace `lapply` with `future_lapply`** when `parallel = TRUE`. Use `future.apply::future_lapply(v_usinas, ajustar_usina, ..., future.seed = TRUE)` to ensure reproducibility.

4. **Modify `ajustar_usina()` signature** to accept pre-filtered irradiance data instead of raw data. The new signature replaces `dt_irrad_prev` with `dt_irrad_prev_filt` (the output of `associa_nwp_usina` + `adicionar_passo_previsao`). Remove the `associa_nwp_usina` and `adicionar_passo_previsao` calls from inside `ajustar_usina()`.

5. **Artifact writing remains sequential** -- the `lapply(seq_along(v_usinas), ...)` that calls `write_model_artifact` must NOT be parallelized (filesystem writes to the same directory).

6. **Update roxygen2 documentation** for both `train_main` and `ajustar_usina`.

### Inputs/Props

- `train_main(args, strategy, parallel)`:
  - `parallel`: logical, default `FALSE`. When `TRUE`, uses `future_lapply` for per-plant processing.
- `ajustar_usina(iu, dt_usinas, dt_ger_obs, dt_irrad_prev_filt, dt_corte_obs, fonte, fator_tolerancia, strategy)`:
  - `dt_irrad_prev_filt`: data.table already processed through `associa_nwp_usina()` + `adicionar_passo_previsao()`, containing columns `id_usina`, `passo_prev`, etc.

### Outputs/Behavior

- When `parallel = FALSE`: behavior is identical to current implementation (same results, same order).
- When `parallel = TRUE`: `setup_parallel_plan()` is called at the beginning, `future_lapply` processes plants concurrently, `reset_parallel_plan()` is called in a `finally` block. Results are numerically identical to sequential mode.
- The hoisting of `associa_nwp_usina` improves performance even in sequential mode (computed once instead of N times).

### Error Handling

- If any plant fails during parallel processing, `future_lapply` will propagate the error. The parallel plan must be cleaned up via `on.exit(reset_parallel_plan(old_plan))` regardless of success or failure.
- If `future` or `future.apply` packages are not available and `parallel = TRUE`, the import mechanism will catch this at package load time (since they are in `Imports` from E03-T001).

## Acceptance Criteria

- [ ] Given `train_main(args, parallel = FALSE)`, when executed, then behavior is identical to the pre-change implementation (same artifacts produced).
- [ ] Given `train_main(args, parallel = TRUE)`, when executed with 2 plants, then both plants are processed and artifacts are written correctly.
- [ ] Given `train_main(args, parallel = TRUE)` and `train_main(args, parallel = FALSE)`, when both are run with the same inputs, then the produced model artifacts are numerically identical.
- [ ] Given `ajustar_usina()` is called, when inspected, then it no longer calls `associa_nwp_usina()` internally.
- [ ] Given `train_main()` is called (either mode), when inspected, then `associa_nwp_usina()` is called exactly once before the loop.
- [ ] Given `parallel = TRUE` and a plant processing error occurs, when the error propagates, then the parallel plan is still cleaned up (no leaked workers).
- [ ] Given existing snapshot tests are run, when compared to baseline, then no regressions are detected.
- [ ] Given `devtools::check()` is run, when it completes, then there are no new ERRORs or WARNINGs.

## Implementation Guide

### Suggested Approach

**Step 1: Hoist `associa_nwp_usina` in `train_main()`**

In `train_main()`, before the `lapply`, add:

```r
# Pre-compute NWP-plant association (once for all plants)
dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)
```

Then pass `dt_irrad_prev_filt` to `ajustar_usina` instead of `dataset$irrad_prev`.

**Step 2: Update `ajustar_usina()` signature**

Change the parameter name from `dt_irrad_prev` to `dt_irrad_prev_filt`. Remove lines 75-76 (the `associa_nwp_usina` and `adicionar_passo_previsao` calls). The filtering at line 77 (`[id_usina == iu & passo_prev == "D+0"]`) remains unchanged since `dt_irrad_prev_filt` already has these columns.

**Step 3: Add `parallel` parameter and conditional dispatch**

```r
train_main <- function(args, strategy = linear_regression_strategy(), parallel = FALSE) {
    conn <- conectamock_pfv(args$input)
    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)
    dataset <- get_dataset(args, conn)

    # Hoist NWP association
    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
    dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)

    if (parallel) {
        old_plan <- setup_parallel_plan()
        on.exit(reset_parallel_plan(old_plan), add = TRUE)
        models <- future.apply::future_lapply(v_usinas, ajustar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            future.seed = TRUE
        )
    } else {
        models <- lapply(v_usinas, ajustar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy
        )
    }

    lapply(seq_along(v_usinas), function(i) {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
    })
}
```

**Step 4: Write tests**

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/train.r` -- hoist associa_nwp_usina, add parallel parameter, replace lapply conditionally
- `/home/rogerio/git/mh-pfv/tests/testthat/test-train.r` -- add parallel tests
- `/home/rogerio/git/mh-pfv/tests/testthat/test-strategy-integration.r` -- verify existing train tests still pass

### Patterns to Follow

- The `on.exit(reset_parallel_plan(old_plan), add = TRUE)` pattern ensures cleanup even on error -- follow this exactly.
- The `test_strategy` mock from `test-strategy-integration.r` should be used for parallel correctness tests (it runs fast, avoids real model fitting).
- Use `registerS3method()` to register the test_strategy mock in test files, as done in `test-strategy-integration.r`.
- Maintain the `strategy` parameter as the last named parameter in signatures for backward compatibility.

### Pitfalls to Avoid

- Do NOT parallelize the artifact-writing `lapply` -- `write_model_artifact` writes to the filesystem and concurrent writes to the same directory can cause race conditions.
- Do NOT pass the raw `dt_irrad_prev` to `ajustar_usina` anymore. The hoisted version includes `id_usina` and `passo_prev` columns that the raw data does not have.
- When using `future_lapply`, data.table objects are automatically serialized to workers. Since `ajustar_usina` only reads from shared data.tables (filtering with `[id_usina == iu]`) and does not modify them, this is safe. However, the `associa_nwp_usina` function modifies `coord_prev` by reference (`coord_prev[, distancia := ...]`) -- this is why it MUST be hoisted out and run before parallelization.
- `future.seed = TRUE` is required for reproducibility. Without it, any stochastic operations inside workers would produce non-deterministic results.
- The `parallel` parameter default is `FALSE` to maintain backward compatibility. Existing callers of `train_main(args)` must not break.

## Testing Requirements

### Unit Tests

File: `tests/testthat/test-train.r` (add to existing)

1. `ajustar_usina()` with pre-filtered irradiance data produces same structure as before.
2. `train_main(args, parallel = FALSE)` produces same artifacts as the original implementation.
3. `train_main(args, parallel = TRUE)` produces artifacts identical to sequential mode.

### Integration Tests

File: `tests/testthat/test-strategy-integration.r` (add to existing)

1. `train_main(config, strategy = test_strategy, parallel = TRUE)` produces same mock artifacts as sequential mode.
2. `train_main(config, strategy = test_strategy, parallel = FALSE)` still passes all existing assertions.

Use `skip_if_not(dir.exists(test_path("data")))` for tests that need the test dataset. Use `withr::local_tempdir()` for artifact output. Use `withr::defer(future::plan("sequential"))` to clean up parallel plans in tests.

## Dependencies

- **Blocked By**: E03-T001 (parallel infrastructure)
- **Blocks**: E03-T003 (parallelize predict)

## Effort Estimate

**Points**: 2
**Confidence**: High
