# E03-T001: Rewrite model-strategy.r

## Objective

Convert `fit_model` from an S3 generic dispatching on `model_strategy` to a regular function with name-based dispatch (`fit_<strategy>`). Convert `predict_model` and `model_metadata` from dispatching on the strategy object to dispatching on the model object's class. Delete all `model_strategy` class infrastructure.

## Dependencies

- E02-T004 (environment tests complete -- codebase stable)

## Files to Modify

| File                 | Action           |
| -------------------- | ---------------- |
| `R/model-strategy.r` | Rewrite entirely |

## Detailed Implementation

### 1. Delete the following functions entirely

- `new_model_strategy(type, ...)` (lines 22-33)
- `fit_model.model_strategy(strategy, dty, dtx, dty_bruta, ...)` (lines 57-59)
- `predict_model.model_strategy(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...)` (lines 85-88)
- `model_metadata.model_strategy(strategy, model, ...)` (lines 110-112)

### 2. Rewrite `fit_model` as a regular function (not S3 generic)

Replace the S3 generic (`UseMethod("fit_model")`) with:

```r
#' Ajusta Modelo por Estrategia
#'
#' Funcao de despacho que resolve `fit_<strategy>` no namespace do pacote
#' e delega o ajuste. Nao e um generico S3 -- o despacho e por convencao
#' de nome.
#'
#' @param strategy string escalar identificando o tipo de modelo
#'   (e.g. `"linear_regression"`)
#' @param dty data.table com dados de geracao observada
#' @param dtx data.table com dados de irradiacao prevista
#' @param dty_bruta data.table com dados de geracao bruta
#' @param ... argumentos adicionais passados a funcao de ajuste
#'
#' @return objeto com classe propria do modelo (e.g. `"linear_regression_model"`)
#'
#' @export
fit_model <- function(strategy, dty, dtx, dty_bruta, ...) {
    stopifnot(is.character(strategy), length(strategy) == 1L)
    fn_name <- paste0("fit_", strategy)
    ns <- asNamespace("mhpfv")
    fn <- get0(fn_name, envir = ns, mode = "function", inherits = FALSE)
    if (is.null(fn)) {
        stop("fit_model nao implementado para estrategia '", strategy, "'")
    }
    fn(dty = dty, dtx = dtx, dty_bruta = dty_bruta, ...)
}
```

Key design decisions (from proposal):

- `asNamespace("mhpfv")` scopes lookup to the package namespace only
- `inherits = FALSE` prevents walking up the search path
- `get0` returns `NULL` if not found (no need for `exists()` + `match.fun()`)
- Error message matches existing format ("nao implementado para estrategia")

### 3. Rewrite `predict_model` as S3 generic dispatching on model

Change signature from `predict_model(strategy, model, ...)` to `predict_model(model, ...)`:

```r
#' Gera Previsoes Usando Modelo Ajustado
#'
#' Generico S3 que despacha no objeto modelo ajustado. Cada classe de modelo
#' deve implementar seu proprio metodo.
#'
#' @param model objeto modelo ajustado retornado por [fit_model()]
#' @param df_ger_usi data.table com geracao observada da usina
#' @param df_irrad_prev data.table com irradiacao prevista
#' @param lim_dados vetor numerico de comprimento 2 com limites
#' @param ... argumentos adicionais
#'
#' @return data.table com previsoes
#'
#' @export
predict_model <- function(model, ...) {
    UseMethod("predict_model")
}

#' @rdname predict_model
#' @export
predict_model.default <- function(model, ...) {
    stop("predict_model nao implementado para modelo de classe '",
        paste(class(model), collapse = "/"), "'")
}
```

### 4. Rewrite `model_metadata` as S3 generic dispatching on model

Change signature from `model_metadata(strategy, model, ...)` to `model_metadata(model, ...)`:

```r
#' Extrai Metadados do Modelo Ajustado
#'
#' Generico S3 que despacha no objeto modelo ajustado.
#'
#' @param model objeto modelo ajustado retornado por [fit_model()]
#' @param ... argumentos adicionais
#'
#' @return lista com metadados do modelo
#'
#' @export
model_metadata <- function(model, ...) {
    UseMethod("model_metadata")
}

#' @rdname model_metadata
#' @export
model_metadata.default <- function(model, ...) {
    stop("model_metadata nao implementado para modelo de classe '",
        paste(class(model), collapse = "/"), "'")
}
```

## Acceptance Criteria

1. `new_model_strategy` function no longer exists in `R/model-strategy.r`
2. `fit_model` is a regular function (not S3 generic) that validates `strategy` is a scalar string and dispatches to `fit_<strategy>` via `get0` scoped to `asNamespace("mhpfv")`
3. `fit_model("nonexistent", ...)` raises an error containing "nao implementado"
4. `predict_model(model, ...)` is an S3 generic with `model` as first argument (not `strategy`)
5. `predict_model.default` raises an error containing class name of the model
6. `model_metadata(model, ...)` is an S3 generic with `model` as first argument (not `strategy`)
7. `model_metadata.default` raises an error containing class name of the model
8. All roxygen2 documentation updated for new signatures
9. No references to `model_strategy` class remain in `R/model-strategy.r`

## Scope Boundaries

- Do NOT modify `R/model-linear-regression.r` (that is E03-T002)
- Do NOT modify `R/artifact.r`, `R/train.r`, `R/predict.r` (that is E03-T003)
- Do NOT modify `NAMESPACE` directly (that is E03-T004)
- Do NOT modify tests (that is E03-T005)
- The package will NOT pass `devtools::check()` after this ticket alone because callers still use the old signatures. This is expected -- subsequent tickets fix the callers.

## Technical Notes

- The old S3method registrations (`fit_model.model_strategy`, `predict_model.model_strategy`, `model_metadata.model_strategy`) in NAMESPACE will become stale after this ticket. They will be cleaned up in E03-T004.
- `fit_model` losing S3 generic status is intentional per the proposal: the input is a string, not an object, so S3 dispatch is semantically wrong.
