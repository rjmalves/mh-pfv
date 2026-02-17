# E03-T003 Parallelize predict_main Per-Plant Processing

## Context

### Background

The `predict_main()` function in `R/predict.r` processes each plant sequentially via `lapply(v_usinas, processar_usina, ...)` at line 55. Like the train pipeline (parallelized in E03-T002), each plant is processed independently: data.tables are filtered by `id_usina`, model artifacts are loaded per-plant, and results are returned as a list. The same `associa_nwp_usina()` hoisting pattern from E03-T002 applies here -- `processar_usina()` calls it at line 133, redundantly recomputing for all plants on every iteration.

The predict pipeline is more complex than train: `processar_usina()` calls `preenche_geracao_unit()` twice (once with cortes=NULL, once with actual cortes), loads model artifacts via `pfvIO:::get_model_artifact()`, and returns a two-element list (`com_cortes`, `sem_cortes`). Post-loop, `organiza_resultados()` combines per-plant results with `rbindlist` -- this operates on the list structure returned by `lapply`/`future_lapply` identically.

### Relation to Epic

This is the second and final pipeline parallelization ticket. It follows the same pattern established in E03-T002 for `train_main`: hoist `associa_nwp_usina`, add a `parallel` parameter, conditionally use `future_lapply`. After this ticket, both pipelines support parallel execution.

### Current State

`R/predict.r` contains:

```r
predict_main <- function(args, strategy = linear_regression_strategy()) {
    conn <- conectamock_pfv(args$input)
    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)
    dataset <- get_dataset(args, conn)

    resultados <- lapply(v_usinas, processar_usina,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_mhg = dataset$mhg,
        dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
        dt_irrad_prev = dataset$irrad_prev,
        dt_corte_obs = dataset$corte,
        fonte = args$ordem_prioridade_fontes,
        fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
        artifact_dir = args$artifact,
        strategy = strategy
    )
    # ... organiza_resultados, coloca_na_antes_inicio, write_melhor_historico_geracao
}
```

Inside `processar_usina()`, line 133:

```r
dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dt_irrad_prev)
dt_irrad_prev_filt_n <- adicionar_passo_previsao(dt_irrad_prev_filt)
irrad_prev <- dt_irrad_prev_filt_n[id_usina == iu & passo_prev == "D+0"]
```

The `pfvIO:::get_model_artifact(iu, artifact_dir)` at line 147 reads RDS files per-plant. These are independent reads to different files, so they are safe for parallel access.

After E03-T002, the parallel infrastructure (`R/parallel.r`) and the `train_main` hoisting pattern are established.

## Specification

### Requirements

1. **Hoist `associa_nwp_usina()`** out of `processar_usina()` and into `predict_main()`. Compute once before the loop and pass the pre-computed `dt_irrad_prev_filt` (after `associa_nwp_usina` + `adicionar_passo_previsao`) to `processar_usina()`.

2. **Add `parallel` parameter** to `predict_main()` signature: `predict_main(args, strategy = linear_regression_strategy(), parallel = FALSE)`. When `FALSE`, use standard `lapply`. When `TRUE`, set up a parallel plan, use `future_lapply`, and tear down the plan.

3. **Replace `lapply` with `future_lapply`** when `parallel = TRUE`. Use `future.apply::future_lapply(v_usinas, processar_usina, ..., future.seed = TRUE)`.

4. **Modify `processar_usina()` signature** to accept `dt_irrad_prev_filt` instead of `dt_irrad_prev`. Remove the `associa_nwp_usina` and `adicionar_passo_previsao` calls from inside `processar_usina()`.

5. **Post-loop processing remains sequential** -- `organiza_resultados()`, `coloca_na_antes_inicio()`, and `write_melhor_historico_geracao()` operate on the combined results and must not be parallelized.

6. **Update roxygen2 documentation** for both `predict_main` and `processar_usina`.

### Inputs/Props

- `predict_main(args, strategy, parallel)`:
  - `parallel`: logical, default `FALSE`. When `TRUE`, uses `future_lapply` for per-plant processing.
- `processar_usina(iu, dt_usinas, dt_ger_obs, dt_mhg, dt_mhg_sem_cortes, dt_irrad_prev_filt, dt_corte_obs, fonte, fator_tolerancia, artifact_dir, strategy)`:
  - `dt_irrad_prev_filt`: data.table already processed through `associa_nwp_usina()` + `adicionar_passo_previsao()`.

### Outputs/Behavior

- When `parallel = FALSE`: behavior is identical to current implementation.
- When `parallel = TRUE`: plants are processed concurrently, then results are combined sequentially. `organiza_resultados()` operates on the same list structure regardless of parallel vs sequential origin.
- `organiza_resultados()` uses `rbindlist(lapply(...))` internally, which operates on indexed list elements. The ordering of results from `future_lapply` matches the input order (this is guaranteed by the future framework), so the results are identical.
- The `pfvIO:::get_model_artifact()` call reads different RDS files per plant (named `<id_usina>.rds`), so concurrent reads are safe.

### Error Handling

- If any plant fails during parallel processing, `future_lapply` propagates the error. The parallel plan is cleaned up via `on.exit(reset_parallel_plan(old_plan))`.
- If `pfvIO:::get_model_artifact()` fails for a specific plant (e.g., missing artifact file), the error propagates from that worker. This is the same behavior as sequential mode.

## Acceptance Criteria

- [ ] Given `predict_main(args, parallel = FALSE)`, when executed, then behavior and outputs are identical to the pre-change implementation.
- [ ] Given `predict_main(args, parallel = TRUE)`, when executed with 2 plants, then both plants are processed and output files are written correctly.
- [ ] Given `predict_main(args, parallel = TRUE)` and `predict_main(args, parallel = FALSE)`, when both are run with the same inputs, then output data.tables are numerically identical.
- [ ] Given `processar_usina()` is called, when inspected, then it no longer calls `associa_nwp_usina()` internally.
- [ ] Given `predict_main()` is called (either mode), when inspected, then `associa_nwp_usina()` is called exactly once before the loop.
- [ ] Given `parallel = TRUE` and a plant processing error occurs, when the error propagates, then the parallel plan is still cleaned up.
- [ ] Given existing snapshot tests are run, when compared to baseline, then no regressions are detected.
- [ ] Given `devtools::check()` is run, when it completes, then there are no new ERRORs or WARNINGs.

## Implementation Guide

### Suggested Approach

**Step 1: Hoist `associa_nwp_usina` in `predict_main()`**

In `predict_main()`, before the `lapply`, add:

```r
# Pre-compute NWP-plant association (once for all plants)
dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)
```

**Step 2: Update `processar_usina()` signature**

Replace `dt_irrad_prev` parameter with `dt_irrad_prev_filt`. Remove lines 133-134 (the `associa_nwp_usina` and `adicionar_passo_previsao` calls). The filtering at line 135 (`[id_usina == iu & passo_prev == "D+0"]`) remains as-is.

**Step 3: Add `parallel` parameter and conditional dispatch**

Follow the exact same pattern from E03-T002's `train_main`:

```r
predict_main <- function(args, strategy = linear_regression_strategy(), parallel = FALSE) {
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
        resultados <- future.apply::future_lapply(v_usinas, processar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_mhg = dataset$mhg,
            dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            artifact_dir = args$artifact,
            strategy = strategy,
            future.seed = TRUE
        )
    } else {
        resultados <- lapply(v_usinas, processar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_mhg = dataset$mhg,
            dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            artifact_dir = args$artifact,
            strategy = strategy
        )
    }

    # Post-loop processing (sequential)
    resultados_organizados <- organiza_resultados(resultados = resultados, v_usinas = v_usinas)
    # ... rest unchanged
}
```

**Step 4: Write tests**

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/predict.r` -- hoist associa_nwp_usina in `predict_main`, update `processar_usina` signature, add parallel parameter
- `/home/rogerio/git/mh-pfv/tests/testthat/test-predict.r` -- add parallel tests
- `/home/rogerio/git/mh-pfv/tests/testthat/test-integration-predict.r` -- verify existing integration tests still pass

### Patterns to Follow

- Replicate the exact pattern from E03-T002: `on.exit(reset_parallel_plan(old_plan), add = TRUE)` for cleanup.
- Use `test_strategy` mock for fast parallel correctness tests, as recommended in the learnings.
- Follow the parameter ordering convention: `parallel` goes after `strategy` as the last named parameter.
- Use `copy()` for data.table objects passed to workers where mutation could occur -- but `processar_usina` already uses `copy()` internally at all mutation boundaries.

### Pitfalls to Avoid

- The `pfvIO:::get_model_artifact()` triple-colon access may cause issues in worker environments because the package namespace might not be fully loaded. If this happens, the workaround is to use `pfvIO::` for exported functions or explicitly load the namespace via `requireNamespace("pfvIO")` at the start of `processar_usina()`. However, since `pfvIO` is in `Imports`, it should be available. Test this path explicitly.
- `organiza_resultados()` modifies data.tables by reference (`:=` to add `id_usina`). This happens on the main process after `future_lapply` returns, so it is safe. Do NOT move this into the parallel loop.
- The two calls to `preenche_geracao_unit()` inside `processar_usina()` are sequential and dependent (the second uses output from the first). They must remain sequential within each worker.
- `data.table` objects serialized to workers lose their external pointer (the internal data.table pointer). Operations on them in workers will transparently reallocate. The `copy()` calls already in place prevent issues.

## Testing Requirements

### Unit Tests

File: `tests/testthat/test-predict.r` (add to existing)

1. `processar_usina()` with pre-filtered irradiance data produces same structure as before.
2. `predict_main(args, parallel = FALSE)` produces same output as the original implementation.
3. `predict_main(args, parallel = TRUE)` produces output identical to sequential mode.

### Integration Tests

File: `tests/testthat/test-integration-predict.r` (add to existing)

1. Full predict pipeline with `parallel = TRUE` using test data produces expected output files.
2. Parallel predict with `test_strategy` mock produces same results as sequential.

Note: Integration tests that read parquet files may fail due to the Arrow ZSTD codec issue in the test environment. Use `skip_if_not()` guards appropriately. Use `withr::defer(future::plan("sequential"))` to clean up parallel plans in tests.

## Dependencies

- **Blocked By**: E03-T002 (parallelize train -- establishes the pattern)
- **Blocks**: E03-T005 (benchmarking infrastructure)

## Effort Estimate

**Points**: 2
**Confidence**: High
