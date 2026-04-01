# E03-T005: Rewrite Tests

## Objective

Update all test files affected by the model strategy simplification to use the new API: string dispatch for `fit_model`, model-class dispatch for `predict_model`/`model_metadata`, new artifact structure, and removed `strategy` parameter from predict pipeline.

## Dependencies

- E03-T003 (artifact + pipeline updates)
- E03-T004 (NAMESPACE updated -- package can load correctly)

## Files to Modify

| File                                                  | Action                                                      |
| ----------------------------------------------------- | ----------------------------------------------------------- |
| `tests/testthat/helper-generators.r`                  | Update `gen_model_artifact` and `gen_model_artifact_legacy` |
| `tests/testthat/test-model-strategy.r`                | Rewrite for new API                                         |
| `tests/testthat/test-strategy-integration.r`          | Rewrite for new API                                         |
| `tests/testthat/test-artifact.r`                      | Update for new artifact structure                           |
| `tests/testthat/test-integration-train.r`             | Update strategy usage                                       |
| `tests/testthat/test-integration-predict.r`           | Remove strategy parameter                                   |
| `tests/testthat/test-preenchimento-dados-faltantes.r` | Update `preenche_geracao_unit` calls                        |

## Detailed Implementation

### 1. `tests/testthat/helper-generators.r`

#### 1a. Update `gen_model_artifact`

The artifact structure changes from `list(id_usina, parametros, metadata)` to `list(id_usina, model, metadata)` where `model` is a classed object.

```r
gen_model_artifact <- function(id_usina = "USI1") {
    hour_names <- sprintf(
        "%02d:%02d",
        rep(5:18, each = 2),
        rep(c(0, 30), times = 14)
    )
    a_values <- seq(0.01, 0.05, length.out = length(hour_names))
    parametros <- data.frame(
        a = a_values,
        b = rep(0, length(hour_names)),
        row.names = hour_names
    )
    model <- structure(
        list(parametros = parametros),
        class = "linear_regression_model"
    )
    metadata <- list(
        type = "linear_regression",
        n_slots = length(hour_names),
        n_valid_slots = length(hour_names),
        timestamp = as.POSIXct("2025-07-01 00:00:00", tz = "UTC"),
        package_version = as.character(utils::packageVersion("mhpfv")),
        config_hash = "test-hash-placeholder"
    )
    list(id_usina = id_usina, model = model, metadata = metadata)
}
```

Key changes:

- `$parametros` field replaced by `$model` containing a `linear_regression_model` object
- The `linear_regression_model` object wraps `parametros` internally
- Tests accessing `artifact$parametros` must change to `artifact$model$parametros`

#### 1b. Update `gen_model_artifact_legacy`

Legacy artifacts (without metadata) also change structure:

```r
gen_model_artifact_legacy <- function(id_usina = "USI1") {
    hour_names <- sprintf(
        "%02d:%02d",
        rep(5:18, each = 2),
        rep(c(0, 30), times = 14)
    )
    a_values <- seq(0.01, 0.05, length.out = length(hour_names))
    parametros <- data.frame(
        a = a_values,
        b = rep(0, length(hour_names)),
        row.names = hour_names
    )
    model <- structure(
        list(parametros = parametros),
        class = "linear_regression_model"
    )
    list(id_usina = id_usina, model = model)
}
```

### 2. `tests/testthat/test-model-strategy.r`

Complete rewrite. The old tests verify `new_model_strategy`, `linear_regression_strategy`, S3 dispatch on strategy objects, and the old signatures. All of these are gone.

#### 2a. Delete tests for removed functions

- Delete all `new_model_strategy` tests (lines 1-34)
- Delete `linear_regression_strategy` tests (lines 96-113)

#### 2b. Rewrite `fit_model` tests

Test string dispatch:

- `fit_model("linear_regression", dty, dtx, dty_bruta)` returns an object with class `"linear_regression_model"`
- `fit_model("nonexistent", ...)` raises error containing "nao implementado"
- `fit_model(123, ...)` raises error (non-string input)
- `fit_model(c("a", "b"), ...)` raises error (non-scalar input)

#### 2c. Rewrite `predict_model` tests

Test model-class dispatch:

- `predict_model(model, ...)` where `model` is a `linear_regression_model` delegates correctly
- `predict_model.default` raises error containing class name for unknown model classes
- Create an unclassed list and verify `.default` fires

#### 2d. Rewrite `model_metadata` tests

Test model-class dispatch:

- `model_metadata(model)` where `model` is a `linear_regression_model` returns correct structure
- `model_metadata.default` raises error containing class name
- Test with model containing NA coefficients
- Test validation of `model$parametros`

#### 2e. Rewrite `fit_model.linear_regression` tests

Replace with `fit_linear_regression` tests:

- `fit_linear_regression(dty, dtx, dty_bruta)` returns `linear_regression_model`
- Result `$parametros` is identical to `ajusta_regressao_ger_irrad(dty, dtx, dty_bruta)`
- Equivalence test: `fit_model("linear_regression", dty, dtx, dty_bruta)` produces same result as `fit_linear_regression(dty, dtx, dty_bruta)`
- Keep the real-data test (with `skip_if_not(dir.exists(test_path("data")))`) but update to use new API

#### 2f. Rewrite `predict_model.linear_regression` tests

Replace with `predict_model.linear_regression_model` tests:

- Create a `linear_regression_model` object (via `structure(list(parametros = model_df), class = "linear_regression_model")`)
- `predict_model(model, df_ger_usi, df_irrad_prev, lim_dados)` produces same output as `substitui_por_estimativas(df_ger_usi, df_irrad_prev, model$parametros, lim_dados)`
- No `strategy` argument

#### 2g. Rewrite custom dispatch test

The old test (lines 69-94) defines `fit_model.test_model`, `predict_model.test_model`, `model_metadata.test_model` using the old strategy-based dispatch. Rewrite for the new API:

```r
test_that("custom model dispatch works with new API", {
    # Define fit_custom in package namespace for get0 lookup
    fit_custom <- function(dty, dtx, dty_bruta, ...) {
        structure(list(fitted = TRUE), class = "custom_model")
    }
    # Temporarily inject into namespace
    ns <- asNamespace("mhpfv")
    env_bind <- get("fit_custom")
    old_val <- ns[["fit_custom"]]
    assign("fit_custom", env_bind, envir = ns)
    on.exit(if (is.null(old_val)) rm("fit_custom", envir = ns)
            else assign("fit_custom", old_val, envir = ns), add = TRUE)

    predict_model.custom_model <- function(model, ...) {
        list(predicted = TRUE)
    }
    model_metadata.custom_model <- function(model, ...) {
        list(name = "custom")
    }
    registerS3method("predict_model", "custom_model",
        predict_model.custom_model, envir = ns)
    registerS3method("model_metadata", "custom_model",
        model_metadata.custom_model, envir = ns)

    fit_result <- fit_model("custom", NULL, NULL, NULL)
    expect_true(fit_result$fitted)
    expect_true(inherits(fit_result, "custom_model"))

    pred_result <- predict_model(fit_result)
    expect_true(pred_result$predicted)

    meta_result <- model_metadata(fit_result)
    expect_equal(meta_result$name, "custom")
})
```

### 3. `tests/testthat/test-strategy-integration.r`

Rewrite the test helpers and integration tests:

#### 3a. Rewrite test strategy helpers

Replace old strategy-based helpers with new model-based helpers:

```r
fit_test_strategy <- function(dty, dtx, dty_bruta, ...) {
    horas <- seq(5.0, 18.5, by = 0.5)
    nomes <- sprintf("%02d:%02d", floor(horas), ifelse(horas %% 1 == 0.5, 30, 0))
    params <- data.frame(
        a = rep(0.5, length(horas)),
        b = rep(0, length(horas)),
        row.names = nomes
    )
    structure(list(parametros = params), class = "test_strategy_model")
}

predict_model.test_strategy_model <- function(model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(df_ger_usi, df_irrad_prev, model$parametros, lim_dados)
}

model_metadata.test_strategy_model <- function(model, ...) {
    list(type = "test_strategy", n_slots = nrow(model$parametros), timestamp = Sys.time())
}
```

Register with `registerS3method` and also inject `fit_test_strategy` into the mhpfv namespace so `fit_model("test_strategy", ...)` can find it.

#### 3b. Update integration tests

- `train_main(config, strategy = "test_strategy")` instead of `strategy = new_model_strategy("test_strategy")`
- Artifact validation: `artifact$model$parametros` instead of `artifact$parametros`
- `predict_model(artifact$model, ...)` instead of `predict_model(strategy, model = artifact$parametros, ...)`
- Remove `strategy` from `predict_main` calls

### 4. `tests/testthat/test-artifact.r`

#### 4a. Update `build_artifact_metadata` tests

Delete all `build_artifact_metadata` tests (lines 1-66) -- function no longer exists.

#### 4b. Update `build_model_artifact` tests

- New signature: `build_model_artifact("USI1", model, cfg)` where `model` is a `linear_regression_model`
- Verify result has `$model` (not `$parametros`)
- Verify `result$model` is the classed object passed in
- Verify `result$metadata` contains all expected fields

#### 4c. Update `validate_artifact` tests

- `gen_model_artifact()` now returns new structure -- tests should work with updated helper
- Update "rejeita artefato sem parametros" to "rejeita artefato sem model"
- Update "rejeita parametros nao-data.frame" to "rejeita model nao-lista"
- Remove "rejeita parametros sem coluna a" (model validation is model-specific, not artifact-level)
- Update "coleta multiplos erros" to check for `model` instead of `parametros`

### 5. `tests/testthat/test-integration-train.r`

- `train_main(config)` still works (uses default `strategy = "linear_regression"`)
- `train_main(config, strategy = strategy)` where `strategy` was `linear_regression_strategy()` changes to: remove the explicit `strategy = strategy` line or pass `strategy = "linear_regression"`
- Artifact structure verification: `artifact$model$parametros` instead of `artifact$parametros`; verify `artifact$model` has class `"linear_regression_model"`
- "train_main accepts custom strategy" test: pass `strategy = "linear_regression"` as string instead of `linear_regression_strategy()`

### 6. `tests/testthat/test-integration-predict.r`

- `predict_main(config_predict)` -- no `strategy` parameter (works with default)
- "predict_main accepts custom strategy" test: remove the `strategy` parameter entirely, or change to verify the default behavior
- "predict_main handles legacy artifacts without metadata": update `gen_model_artifact_legacy()` call (already updated in helper) and ensure artifacts written to disk have the new structure
- Remove `strategy = strategy` from any `predict_main` calls

### 7. `tests/testthat/test-preenchimento-dados-faltantes.r`

#### 7a. Update `preenche_geracao_unit` calls

Remove `strategy` parameter from all calls. The `model` parameter changes from the full artifact to the classed model object:

Old:

```r
model <- list(
    id_usina = "U1",
    parametros = data.frame(a = rep(1, 2), b = rep(0, 2), row.names = c("06:00", "06:30"))
)
resultado <- preenche_geracao_unit(..., model = model)
```

New:

```r
model <- structure(
    list(parametros = data.frame(a = rep(1, 2), b = rep(0, 2), row.names = c("06:00", "06:30"))),
    class = "linear_regression_model"
)
resultado <- preenche_geracao_unit(..., model = model)
```

Apply this change to all 6 `preenche_geracao_unit` calls in the test file. The `model` is now a classed object, not a raw artifact list.

#### 7b. No changes to `substitui_por_estimativas` tests

`substitui_por_estimativas` is an internal function that still takes `(df_ger_usi, df_irrad_prev, regressoes, lim_dados)`. Its tests are unchanged.

#### 7c. No changes to `zera_horarios_extremos` or `aplica_cortes_em_geracao` tests

These functions are unchanged.

## Acceptance Criteria

1. `gen_model_artifact()` returns artifact with `$model` (classed `linear_regression_model`) instead of `$parametros`
2. `gen_model_artifact_legacy()` returns artifact with `$model` (classed) instead of `$parametros`
3. No references to `new_model_strategy()` or `linear_regression_strategy()` in any test file
4. No references to `build_artifact_metadata()` in any test file
5. All `fit_model` tests use string first argument (e.g. `fit_model("linear_regression", ...)`)
6. All `predict_model` tests use model object as first argument (e.g. `predict_model(model, ...)`)
7. All `model_metadata` tests use model object as first argument
8. All `preenche_geracao_unit` calls have no `strategy` parameter and pass classed model objects
9. All `predict_main` calls have no `strategy` parameter
10. All `train_main` calls that explicitly pass `strategy` use a string value
11. Custom dispatch test verifies `fit_model("custom", ...)` -> `fit_custom()` -> classed object -> `predict_model` dispatches on model class
12. `devtools::test()` passes with all tests green

## Scope Boundaries

- Do NOT modify source files in `R/` (those were done in E03-T001 through E03-T004)
- Do NOT add new test files -- modify existing ones
- Do NOT change tests unrelated to model strategy (e.g. provenance, metrics, health-report tests)

## Technical Notes

- The custom dispatch test (`test-strategy-integration.r`) requires injecting `fit_test_strategy` into the `mhpfv` namespace at test time. Use `assign("fit_test_strategy", ..., envir = asNamespace("mhpfv"))` with `on.exit` cleanup.
- `registerS3method` is needed for `predict_model.test_strategy_model` and `model_metadata.test_strategy_model` at test time.
- Tests that use `test_path("data")` and real data should work as before, since the actual regression computation (`ajusta_regressao_ger_irrad`) is unchanged -- only the wrapper and return type changed.
