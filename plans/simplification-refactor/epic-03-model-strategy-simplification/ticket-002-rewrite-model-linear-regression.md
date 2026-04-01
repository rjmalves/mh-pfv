# E03-T002: Rewrite model-linear-regression.r

## Objective

Rewrite `R/model-linear-regression.r` so that `fit_linear_regression` returns an S3 object with class `"linear_regression_model"`, and `predict_model`/`model_metadata` methods dispatch on that class instead of the old `"linear_regression"` strategy class.

## Dependencies

- E03-T001 (model-strategy.r rewrite -- generics now dispatch on model)

## Files to Modify

| File                          | Action           |
| ----------------------------- | ---------------- |
| `R/model-linear-regression.r` | Rewrite entirely |

## Detailed Implementation

### 1. Delete the following functions entirely

- `linear_regression_strategy(...)` (lines 22-24) -- constructor for old strategy object
- `fit_model.linear_regression(strategy, dty, dtx, dty_bruta, ...)` (lines 37-39) -- old S3 method
- `predict_model.linear_regression(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...)` (lines 54-62) -- old S3 method
- `model_metadata.linear_regression(strategy, model, ...)` (lines 81-93) -- old S3 method

### 2. Write `fit_linear_regression`

This is the function `fit_model` will dispatch to via `get0("fit_linear_regression", envir = ns)`.

```r
#' Ajusta Modelo de Regressao Linear
#'
#' Ajusta regressoes lineares por horario entre geracao observada e
#' irradiacao prevista. Retorna objeto com classe `"linear_regression_model"`.
#'
#' @param dty data.table com dados de geracao observada
#' @param dtx data.table com dados de irradiacao prevista
#' @param dty_bruta data.table com dados de geracao bruta
#' @param ... argumentos adicionais (ignorados)
#'
#' @return objeto S3 com classe `"linear_regression_model"` contendo:
#' \describe{
#'   \item{`parametros`}{data.frame com coeficientes `a` e `b` indexados por horario}
#' }
#'
#' @seealso [fit_model()], [predict_model.linear_regression_model()],
#'   [model_metadata.linear_regression_model()]
#'
#' @export
fit_linear_regression <- function(dty, dtx, dty_bruta, ...) {
    params <- ajusta_regressao_ger_irrad(dty = dty, dtx = dtx, dty_bruta = dty_bruta)
    structure(
        list(parametros = params),
        class = "linear_regression_model"
    )
}
```

Design decisions:

- Class name is `"linear_regression_model"` (not namespaced) per proposal
- The returned object wraps `parametros` in a list with class attribute
- `ajusta_regressao_ger_irrad` stays in `train.r` (it is a data-processing function, not model-specific logic)
- No `strategy` parameter -- this function is called directly by `fit_model`

### 3. Write `predict_model.linear_regression_model`

```r
#' @rdname predict_model
#'
#' @details
#' ## Metodo `linear_regression_model`
#'
#' Delega para [substitui_por_estimativas()], usando `model$parametros`
#' como coeficientes de regressao.
#'
#' @export
predict_model.linear_regression_model <- function(model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(
        df_ger_usi = df_ger_usi,
        df_irrad_prev = df_irrad_prev,
        regressoes = model$parametros,
        lim_dados = lim_dados
    )
}
```

Key change from old signature: first argument is now `model` (the classed object), not `strategy`. The method accesses `model$parametros` internally to get the coefficients data.frame.

### 4. Write `model_metadata.linear_regression_model`

```r
#' @rdname model_metadata
#'
#' @details
#' ## Metodo `linear_regression_model`
#'
#' Extrai metadados do modelo de regressao linear. Valida que
#' `model$parametros` e um `data.frame` contendo a coluna `a`.
#'
#' @return Para `linear_regression_model`, lista com:
#' \describe{
#'   \item{`type`}{`"linear_regression"`}
#'   \item{`n_slots`}{numero total de horarios no modelo}
#'   \item{`n_valid_slots`}{numero de horarios com coeficiente `a` nao-`NA`}
#'   \item{`timestamp`}{momento da extracao (`Sys.time()`)}
#' }
#'
#' @export
model_metadata.linear_regression_model <- function(model, ...) {
    params <- model$parametros
    stopifnot(
        is.data.frame(params),
        "a" %in% names(params)
    )
    list(
        type = "linear_regression",
        n_slots = nrow(params),
        n_valid_slots = sum(!is.na(params$a)),
        timestamp = Sys.time()
    )
}
```

Key change: extracts `model$parametros` from the classed object instead of receiving `model` as a bare data.frame.

## Acceptance Criteria

1. `linear_regression_strategy()` no longer exists in `R/model-linear-regression.r`
2. `fit_linear_regression(dty, dtx, dty_bruta)` exists and is exported
3. `fit_linear_regression` returns an object with `class(result) == "linear_regression_model"`
4. The returned object has `result$parametros` as a data.frame identical to what `ajusta_regressao_ger_irrad` returns
5. `predict_model.linear_regression_model(model, df_ger_usi, df_irrad_prev, lim_dados)` exists with `model` as first arg
6. `predict_model.linear_regression_model` produces output identical to `substitui_por_estimativas(df_ger_usi, df_irrad_prev, model$parametros, lim_dados)`
7. `model_metadata.linear_regression_model(model)` exists with `model` as first arg
8. `model_metadata.linear_regression_model` returns list with `type`, `n_slots`, `n_valid_slots`, `timestamp`
9. `model_metadata.linear_regression_model` validates `model$parametros` is a data.frame with column `a`
10. All roxygen2 documentation updated for new signatures

## Scope Boundaries

- Do NOT modify `R/model-strategy.r` (done in E03-T001)
- Do NOT modify `R/artifact.r`, `R/train.r`, `R/predict.r`, `R/preenchimento-dados-faltantes.r` (that is E03-T003)
- Do NOT modify `NAMESPACE` directly (that is E03-T004)
- Do NOT modify tests (that is E03-T005)
- Do NOT move `ajusta_regressao_ger_irrad` -- it stays in `R/train.r`
- The package will NOT pass `devtools::check()` after this ticket because callers still use old signatures.

## Technical Notes

- `fit_linear_regression` must be discoverable by `get0("fit_linear_regression", envir = asNamespace("mhpfv"))`. This requires the function to be defined in a file under `R/` (which it is) and the package to be loaded. The `@export` tag ensures it appears in the namespace.
- Old S3method registrations (`fit_model.linear_regression`, `predict_model.linear_regression`, `model_metadata.linear_regression`) will be stale. Cleanup is in E03-T004.
