# E02-T004 Refactor predict.r to Use Model Strategy

## Context

### Background

With the strategy pattern in place for training (E02-T003), the predict pipeline must also be refactored to use the strategy for the imputation step. Currently, `preenche_geracao_unit()` calls `substitui_por_estimativas()` directly. After this refactor, it will call `predict_model(strategy, ...)` which dispatches to the appropriate implementation.

### Relation to Epic

Depends on E02-T003 (train refactor). This completes the strategy pattern integration across both pipelines. Blocks E02-T006 (comprehensive strategy tests).

### Current State

In `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`, `preenche_geracao_unit()` (line 48-49) calls:

```r
geracao_usina_completo <- substitui_por_estimativas(
    df_ger_usi = copy(geracao_usina),
    df_irrad_prev = copy(irrad_prev),
    regressoes = model[[2]],
    lim_dados = limite_dados
)
```

The call chain is: `predict_main()` -> `processar_usina()` -> `preenche_geracao_unit()` -> `substitui_por_estimativas()`.

The model artifact is loaded via `pfvIO:::get_model_artifact(iu, artifact_dir)` which returns `list(id_usina, parametros)`. The parametros (`model[[2]]`) is passed to `substitui_por_estimativas` as `regressoes`.

## Specification

### Requirements

1. Add `strategy` parameter to `predict_main()` (default: `linear_regression_strategy()`)
2. Pass strategy through: `predict_main()` -> `processar_usina()` -> `preenche_geracao_unit()`
3. In `preenche_geracao_unit()`, replace `substitui_por_estimativas(...)` with `predict_model(strategy, model[[2]], ...)`
4. Artifact loading and format remain unchanged
5. Default behavior (no strategy argument) must be identical to current
6. All existing tests and snapshot tests must pass

### Inputs/Props

- `strategy` parameter: S3 object of class `model_strategy` (default: `linear_regression_strategy()`)
- All other inputs unchanged

### Outputs/Behavior

- Output Parquet files are byte-for-byte identical when using the default strategy
- The `status` column values are identical

### Error Handling

Same error handling as current code -- errors propagate from the strategy implementation.

## Acceptance Criteria

- [ ] Given `predict_main(config)` called without strategy, when run, then output is identical to current version
- [ ] Given `predict_main(config, strategy = linear_regression_strategy())`, when run, then output is identical
- [ ] Given all existing tests, when run, then they pass unchanged
- [ ] Given snapshot tests from E01-T006, when run, then they pass (numerical equivalence)
- [ ] Given `R CMD check` and `lintr`, when run, then they pass with no new warnings
- [ ] Given `preenche_geracao_unit()`, when its signature is inspected, then it includes `strategy` parameter

## Implementation Guide

### Suggested Approach

1. Modify `predict_main()` in `/home/rogerio/git/mh-pfv/R/predict.r`:

Add `strategy = linear_regression_strategy()` parameter and pass it through to `processar_usina()`.

2. Modify `processar_usina()` in `/home/rogerio/git/mh-pfv/R/predict.r`:

Add `strategy` parameter and pass it to both calls to `preenche_geracao_unit()`.

3. Modify `preenche_geracao_unit()` in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`:

Add `strategy = linear_regression_strategy()` parameter and replace:

```r
geracao_usina_completo <- substitui_por_estimativas(
    df_ger_usi = copy(geracao_usina),
    df_irrad_prev = copy(irrad_prev),
    regressoes = model[[2]],
    lim_dados = limite_dados
)
```

With:

```r
geracao_usina_completo <- predict_model(strategy,
    model = model[[2]],
    df_ger_usi = copy(geracao_usina),
    df_irrad_prev = copy(irrad_prev),
    lim_dados = limite_dados
)
```

4. Run all tests including snapshots
5. Run `devtools::document()`, `devtools::check()`, `lintr::lint_package()`

### Key Files to Modify

- **Modify**: `/home/rogerio/git/mh-pfv/R/predict.r` (add strategy to predict_main and processar_usina)
- **Modify**: `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r` (add strategy to preenche_geracao_unit, replace direct call)
- **Auto-generated**: Man pages for modified functions

### Patterns to Follow

- Same pattern as E02-T003: default parameter, pass through call chain
- Preserve all `copy()` calls on data.tables
- Keep the `model[[2]]` access pattern (parametros from the artifact list)

### Pitfalls to Avoid

- `preenche_geracao_unit()` is called TWICE in `processar_usina()` (lines 153 and 169) -- both calls must pass the strategy
- Do NOT remove `substitui_por_estimativas()` -- it remains as the underlying implementation
- The `model` parameter in `preenche_geracao_unit` is the full artifact list, but `predict_model` receives `model[[2]]` (the parametros data.frame) -- ensure this indexing is preserved
- Update the roxygen2 `@param` documentation for all modified functions
- The existing test `test-preenchimento-dados-faltantes.r` calls `preenche_geracao_unit()` directly -- it must still work without a strategy argument (default)

## Testing Requirements

### Unit Tests

Existing tests in `test-preenchimento-dados-faltantes.r` and `test-predict.r` must pass unchanged. Add:

```r
test_that("predict_main accepts custom strategy", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))

    config_train <- gen_config(mode = "train")
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    config_predict <- gen_config(mode = "predict")
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict$output <- temp_output
    config_predict <- parse_config(config_predict, conn)

    strategy <- linear_regression_strategy()
    expect_no_error(predict_main(config_predict, strategy = strategy))
})
```

### Integration Tests

Existing integration tests from E01-T005 must pass unchanged.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E02-T003
- **Blocks**: E02-T006

## Effort Estimate

**Points**: 2
**Confidence**: High
