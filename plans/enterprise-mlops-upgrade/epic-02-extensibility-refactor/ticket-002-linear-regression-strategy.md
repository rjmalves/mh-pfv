# E02-T002 Wrap Existing Linear Regression as Strategy Implementation

## Context

### Background

The current linear regression algorithm in `ajusta_regressao_ger_irrad()` and `substitui_por_estimativas()` must be wrapped as the first concrete implementation of the S3 model strategy interface defined in E02-T001. This creates the `linear_regression` class methods: `fit_model.linear_regression()`, `predict_model.linear_regression()`, and `model_metadata.linear_regression()`. The implementation must produce byte-for-byte identical numerical results to the current code.

### Relation to Epic

This ticket depends on E02-T001 (strategy interface). It is a prerequisite for E02-T003 (refactor train.r) and E02-T004 (refactor predict.r), which will call the strategy methods instead of the direct functions.

### Current State

**Fitting** (`ajusta_regressao_ger_irrad` in `/home/rogerio/git/mh-pfv/R/train.r`, lines 161-236):

- Iterates over half-hour slots from 05:00 to 18:30
- For each slot: filters dty and dtx by hour/minute, joins on id_usina and datetime, fits `lm(y ~ x + 0)`
- Falls back to 70th percentile filtering if fewer than 10 valid pairs
- Returns `data.frame(a = ..., b = 0, row.names = "HH:MM")`

**Prediction** (`substitui_por_estimativas` in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`, lines 108-141):

- Adds `hora_min` column from datetime, merges with regression coefficients
- Computes `ger_est = a * valor` (irradiance)
- Replaces NA positions in generation with estimates
- Applies limit bounds, updates status to 4

## Specification

### Requirements

1. Create S3 methods in `/home/rogerio/git/mh-pfv/R/model-linear-regression.r`:
   - `fit_model.linear_regression(strategy, dty, dtx, dty_bruta, ...)`
   - `predict_model.linear_regression(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...)`
   - `model_metadata.linear_regression(strategy, model, ...)`
2. `fit_model.linear_regression()` must delegate to the existing `ajusta_regressao_ger_irrad()` function -- do NOT duplicate the algorithm code
3. `predict_model.linear_regression()` must delegate to the existing `substitui_por_estimativas()` function -- do NOT duplicate the algorithm code
4. `model_metadata.linear_regression()` must return a list with: `type`, `n_slots`, `n_valid_slots`, `mean_coefficient`, `timestamp`
5. The existing functions `ajusta_regressao_ger_irrad()` and `substitui_por_estimativas()` must NOT be modified in this ticket -- they remain as internal package functions
6. Add a convenience constructor `linear_regression_strategy()` that returns `new_model_strategy("linear_regression")`

### Inputs/Props

Same as the generic definitions in E02-T001, with the concrete types:

- `fit_model.linear_regression`: dty/dtx/dty_bruta are data.tables matching the current function signatures
- `predict_model.linear_regression`: model is the data.frame of coefficients (parametros from the artifact)
- `model_metadata.linear_regression`: model is the same data.frame

### Outputs/Behavior

- `fit_model.linear_regression()` returns the same `data.frame` as `ajusta_regressao_ger_irrad()` -- identical output
- `predict_model.linear_regression()` returns the same modified `df_ger_usi` as `substitui_por_estimativas()` -- identical output
- `model_metadata.linear_regression()` returns `list(type = "linear_regression", n_slots = nrow(model), n_valid_slots = sum(!is.na(model$a)), mean_coefficient = mean(model$a, na.rm = TRUE), timestamp = Sys.time())`

### Error Handling

- If `model` is not a data.frame with column `a`, raise `stop("Modelo invalido: esperado data.frame com coluna 'a'")`
- If dty or dtx are empty data.tables, delegate to the existing function which handles this gracefully

## Acceptance Criteria

- [ ] Given `linear_regression_strategy()`, when called, then it returns an S3 object with classes `c("linear_regression", "model_strategy")`
- [ ] Given `fit_model(strategy, dty, dtx, dty_bruta)` with the linear regression strategy, when called with the same inputs as `ajusta_regressao_ger_irrad(dty, dtx, dty_bruta)`, then both return identical data.frames
- [ ] Given `predict_model(strategy, model, df_ger_usi, df_irrad_prev, lim_dados)`, when called with the same inputs as `substitui_por_estimativas(df_ger_usi, df_irrad_prev, model, lim_dados)`, then both return identical data.tables
- [ ] Given `model_metadata(strategy, model)`, when called, then it returns a list with keys `type`, `n_slots`, `n_valid_slots`, `mean_coefficient`, `timestamp`
- [ ] Given the existing tests for `ajusta_regressao_ger_irrad` and `substitui_por_estimativas`, when run, then they still pass (functions are not modified)
- [ ] Given snapshot tests from E01-T006, when run, then they pass (numerical equivalence)
- [ ] Given `R CMD check` and `lintr`, when run, then they pass with no new warnings

## Implementation Guide

### Suggested Approach

Create `/home/rogerio/git/mh-pfv/R/model-linear-regression.r`:

```r
#' Cria Estrategia de Regressao Linear
#'
#' Construtor de conveniencia para a estrategia de regressao linear sem intercepto.
#' Este e o modelo padrao do pacote mhpfv.
#'
#' @return objeto S3 de classe `c("linear_regression", "model_strategy")`
#'
#' @export
linear_regression_strategy <- function() {
    new_model_strategy("linear_regression")
}

#' @rdname fit_model
#' @export
fit_model.linear_regression <- function(strategy, dty, dtx, dty_bruta, ...) {
    ajusta_regressao_ger_irrad(dty = dty, dtx = dtx, dty_bruta = dty_bruta)
}

#' @rdname predict_model
#' @export
predict_model.linear_regression <- function(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(
        df_ger_usi = df_ger_usi,
        df_irrad_prev = df_irrad_prev,
        regressoes = model,
        lim_dados = lim_dados
    )
}

#' @rdname model_metadata
#' @export
model_metadata.linear_regression <- function(strategy, model, ...) {
    stopifnot(is.data.frame(model), "a" %in% names(model))
    list(
        type = "linear_regression",
        n_slots = nrow(model),
        n_valid_slots = sum(!is.na(model$a)),
        mean_coefficient = mean(model$a, na.rm = TRUE),
        timestamp = Sys.time()
    )
}
```

After creating the file:

1. Run `devtools::document()` to regenerate NAMESPACE
2. Run existing tests: `devtools::test()` -- all must pass
3. Run snapshot tests specifically: verify numerical equivalence
4. Run `devtools::check()` and `lintr::lint_package()`

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/R/model-linear-regression.r`
- **Auto-generated**: `/home/rogerio/git/mh-pfv/NAMESPACE` (via devtools::document)
- **Auto-generated**: Man pages for the new methods

### Patterns to Follow

- Delegate to existing functions -- do NOT copy their implementation
- Use `@rdname fit_model` to group method documentation with the generic
- Follow the existing code style: 4-space indentation, snake_case, Portuguese error messages

### Pitfalls to Avoid

- Do NOT modify `ajusta_regressao_ger_irrad()` or `substitui_por_estimativas()` in this ticket
- Do NOT rename the existing functions -- they remain as internal helpers
- The `predict_model.linear_regression` method must pass `regressoes = model` (note the parameter name mapping from `model` to `regressoes`)
- Ensure `@export` is on each method, not just the generic

## Testing Requirements

### Unit Tests

Add to `/home/rogerio/git/mh-pfv/tests/testthat/test-model-strategy.r`:

```r
test_that("linear_regression_strategy creates correct object", {
    s <- linear_regression_strategy()
    expect_true(inherits(s, "linear_regression"))
    expect_true(inherits(s, "model_strategy"))
})

test_that("fit_model.linear_regression matches ajusta_regressao_ger_irrad", {
    # Use the same test data as test-train.r
    horarios <- seq(from = as.POSIXct("2025-01-01 06:00"), by = "1 day", length.out = 10)
    dtx <- data.table(id_usina = "U1", data_hora_previsao = horarios, valor = seq(10, 100, by = 10))
    dty <- data.table(id_usina = "U1", data_hora_observacao = horarios, valor = seq(2, 20, by = 2))

    strategy <- linear_regression_strategy()
    result_strategy <- fit_model(strategy, copy(dty), copy(dtx), copy(dty))
    result_direct <- ajusta_regressao_ger_irrad(copy(dty), copy(dtx), copy(dty))

    expect_equal(result_strategy, result_direct)
})

test_that("model_metadata.linear_regression returns correct structure", {
    strategy <- linear_regression_strategy()
    model <- data.frame(a = c(0.2, 0.3, NA), b = c(0, 0, 0), row.names = c("06:00", "06:30", "07:00"))
    meta <- model_metadata(strategy, model)

    expect_equal(meta$type, "linear_regression")
    expect_equal(meta$n_slots, 3)
    expect_equal(meta$n_valid_slots, 2)
    expect_equal(meta$mean_coefficient, 0.25)
    expect_true(inherits(meta$timestamp, "POSIXct"))
})
```

### Integration Tests

Equivalence verification through snapshot tests (already in E01-T006).

### E2E Tests

None.

## Dependencies

- **Blocked By**: E02-T001
- **Blocks**: E02-T003, E02-T004

## Effort Estimate

**Points**: 2
**Confidence**: High
