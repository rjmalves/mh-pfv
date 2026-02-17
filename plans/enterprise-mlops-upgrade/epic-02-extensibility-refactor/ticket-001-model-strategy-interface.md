# E02-T001 Design and Implement S3 Model Strategy Interface

## Context

### Background

The mhpfv package currently has a hardcoded linear regression algorithm in `ajusta_regressao_ger_irrad()` (train.r) and `substitui_por_estimativas()` (preenchimento-dados-faltantes.r). To support future model types (e.g., random forest, gradient boosting, quantile regression) without modifying existing code, we need an S3-class strategy pattern. This follows the R convention of using S3 generics and methods for polymorphism, matching the existing pattern in the codebase (e.g., `parsearg_janela()` already uses S3 dispatch).

### Relation to Epic

This is the foundational ticket for the Extensibility Refactor epic. It defines the abstract interface that E02-T002 (linear regression implementation), E02-T003 (train refactor), and E02-T004 (predict refactor) all depend on.

### Current State

The current model fitting and prediction code:

- **Fitting**: `ajusta_regressao_ger_irrad(dty, dtx, dty_bruta)` in `/home/rogerio/git/mh-pfv/R/train.r` returns a `data.frame` with columns `a`, `b` and row names as "HH:MM" strings
- **Prediction**: `substitui_por_estimativas(df_ger_usi, df_irrad_prev, regressoes, lim_dados)` in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r` uses the `regressoes` data.frame to compute `ger_est = a * irrad`
- **Artifact format**: `list(id_usina = "X", parametros = data.frame(a = ..., b = ..., row.names = ...))` serialized as RDS
- S3 dispatch is already used in the codebase: `parsearg_janela()` dispatches on `numeric` vs `character` class

## Specification

### Requirements

1. Create a new file `/home/rogerio/git/mh-pfv/R/model-strategy.r` containing:
   - An S3 constructor function `new_model_strategy(type, ...)` that creates an object with class `c(type, "model_strategy")`
   - Three S3 generics: `fit_model()`, `predict_model()`, `model_metadata()`
   - A default method for each generic that raises an informative error
2. The interface must be minimal -- only 3 generics -- to keep complexity low
3. All generics must have roxygen2 documentation with `@export` tags
4. The strategy object must carry configuration (e.g., model type name, hyperparameters) as attributes or list elements

### Inputs/Props

**`fit_model(strategy, dty, dtx, dty_bruta, ...)`**:

- `strategy`: S3 object of class `model_strategy`
- `dty`: data.table of observed generation (columns: id_usina, data_hora_observacao, valor)
- `dtx`: data.table of predicted irradiance (columns: id_usina, data_hora_previsao, valor)
- `dty_bruta`: data.table of raw observed generation (same schema as dty)
- Returns: a model-specific fitted object (for linear_regression: the existing data.frame)

**`predict_model(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...)`**:

- `strategy`: S3 object of class `model_strategy`
- `model`: fitted model object (output of `fit_model`)
- `df_ger_usi`: data.table of generation to fill
- `df_irrad_prev`: data.table of irradiance predictions
- `lim_dados`: numeric vector of length 2 (lower, upper limits)
- Returns: data.table with filled values (same schema as df_ger_usi, with status updated)

**`model_metadata(strategy, model, ...)`**:

- `strategy`: S3 object of class `model_strategy`
- `model`: fitted model object
- Returns: named list of metadata (type, timestamp, n_params, summary stats)

### Outputs/Behavior

- `new_model_strategy("linear_regression")` creates an object with class `c("linear_regression", "model_strategy")`
- `fit_model(strategy, ...)` dispatches to `fit_model.linear_regression()`
- `predict_model(strategy, ...)` dispatches to `predict_model.linear_regression()`
- `model_metadata(strategy, ...)` dispatches to `model_metadata.linear_regression()`
- Default methods for all three generics raise `stop("Method not implemented for class: ...", class(strategy)[1])`

### Error Handling

- `new_model_strategy(type)` must validate that `type` is a single non-empty character string
- Default methods must produce clear error messages indicating which strategy class is missing an implementation
- `fit_model()` and `predict_model()` must validate that `strategy` inherits from `"model_strategy"`

## Acceptance Criteria

- [ ] Given the file `/home/rogerio/git/mh-pfv/R/model-strategy.r` exists, when `devtools::document()` is run, then `fit_model`, `predict_model`, `model_metadata`, and `new_model_strategy` appear in NAMESPACE
- [ ] Given `new_model_strategy("linear_regression")`, when the result is inspected, then `inherits(result, "model_strategy")` is TRUE and `inherits(result, "linear_regression")` is TRUE
- [ ] Given a strategy object with no method implementation, when `fit_model(strategy, ...)` is called, then it raises an error containing "not implemented"
- [ ] Given the roxygen2 documentation, when `man/` pages are generated, then documentation exists for all 4 exported functions
- [ ] Given `R CMD check`, when run, then it passes with no new warnings
- [ ] Given `lintr::lint_package()`, when run, then no lint errors are reported for `model-strategy.r`

## Implementation Guide

### Suggested Approach

Create `/home/rogerio/git/mh-pfv/R/model-strategy.r` with:

```r
#' Cria Um Novo Objeto de Estrategia de Modelo
#'
#' Construtor S3 para objetos de estrategia de modelo. O tipo determina
#' qual implementacao de `fit_model()`, `predict_model()` e `model_metadata()`
#' sera utilizada via despacho de metodos S3.
#'
#' @param type string indicando o tipo de modelo (ex: "linear_regression")
#' @param ... parametros adicionais armazenados como atributos da estrategia
#'
#' @return objeto S3 com classe `c(type, "model_strategy")`
#'
#' @export
new_model_strategy <- function(type, ...) {
    stopifnot(
        is.character(type),
        length(type) == 1L,
        nchar(type) > 0L
    )
    params <- list(...)
    structure(
        list(type = type, params = params),
        class = c(type, "model_strategy")
    )
}

#' Ajusta Modelo de Acordo com a Estrategia
#'
#' Generico S3 para ajuste de modelos. Cada implementacao concreta
#' (ex: `fit_model.linear_regression`) define como o modelo e treinado.
#'
#' @param strategy objeto de estrategia de modelo (classe `model_strategy`)
#' @param dty data.table de geracao observada
#' @param dtx data.table de irradiancia prevista
#' @param dty_bruta data.table de geracao observada bruta
#' @param ... parametros adicionais
#'
#' @return objeto de modelo ajustado (formato depende da implementacao)
#'
#' @export
fit_model <- function(strategy, dty, dtx, dty_bruta, ...) {
    UseMethod("fit_model")
}

#' @rdname fit_model
#' @export
fit_model.model_strategy <- function(strategy, dty, dtx, dty_bruta, ...) {
    stop(paste0(
        "Metodo fit_model() nao implementado para classe: ",
        class(strategy)[1]
    ))
}

#' Aplica Modelo para Preenchimento de Dados Faltantes
#'
#' Generico S3 para aplicacao de modelos treinados. Cada implementacao
#' concreta define como os dados faltantes sao preenchidos.
#'
#' @param strategy objeto de estrategia de modelo (classe `model_strategy`)
#' @param model objeto de modelo ajustado (saida de `fit_model()`)
#' @param df_ger_usi data.table de geracao da usina
#' @param df_irrad_prev data.table de irradiancia prevista
#' @param lim_dados vetor numerico com limites inferior e superior
#' @param ... parametros adicionais
#'
#' @return data.table com valores preenchidos
#'
#' @export
predict_model <- function(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...) {
    UseMethod("predict_model")
}

#' @rdname predict_model
#' @export
predict_model.model_strategy <- function(strategy, model, df_ger_usi, df_irrad_prev, lim_dados, ...) {
    stop(paste0(
        "Metodo predict_model() nao implementado para classe: ",
        class(strategy)[1]
    ))
}

#' Retorna Metadados do Modelo Ajustado
#'
#' Generico S3 para extracao de metadados de modelos. Util para
#' rastreabilidade e comparacao de modelos.
#'
#' @param strategy objeto de estrategia de modelo (classe `model_strategy`)
#' @param model objeto de modelo ajustado (saida de `fit_model()`)
#' @param ... parametros adicionais
#'
#' @return lista nomeada com metadados do modelo
#'
#' @export
model_metadata <- function(strategy, model, ...) {
    UseMethod("model_metadata")
}

#' @rdname model_metadata
#' @export
model_metadata.model_strategy <- function(strategy, model, ...) {
    stop(paste0(
        "Metodo model_metadata() nao implementado para classe: ",
        class(strategy)[1]
    ))
}
```

After creating the file:

1. Run `devtools::document()` to regenerate NAMESPACE and man pages
2. Run `devtools::check()` to verify
3. Run `lintr::lint_package()` to verify
4. Add `"fit_model"`, `"predict_model"`, `"model_metadata"` to `utils::globalVariables()` in `zzz.r` if needed (unlikely since they are generics, not NSE column names)

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/R/model-strategy.r`
- **Auto-generated**: `/home/rogerio/git/mh-pfv/NAMESPACE` (via devtools::document)
- **Auto-generated**: `/home/rogerio/git/mh-pfv/man/new_model_strategy.Rd`, `man/fit_model.Rd`, `man/predict_model.Rd`, `man/model_metadata.Rd`

### Patterns to Follow

- Follow the existing S3 pattern in `/home/rogerio/git/mh-pfv/R/config-file.r` where `parsearg_janela()` uses `UseMethod()`
- Use Portuguese for error messages and function descriptions (matching codebase convention in roxygen2 docs)
- Use `structure()` for S3 object construction (standard R pattern)
- Keep the generic signatures wide (accept `...`) to allow future implementations to receive additional parameters

### Pitfalls to Avoid

- Do NOT name the generic `predict()` -- that conflicts with `stats::predict()`. Use `predict_model()` instead.
- Do NOT add any concrete implementations in this file -- those go in E02-T002
- Do NOT modify any existing files other than NAMESPACE (auto-generated)
- The default methods should use the first class name `class(strategy)[1]` in error messages, not the full class vector
- Ensure roxygen2 `@export` tags are on both the generic AND the default method

## Testing Requirements

### Unit Tests

Add tests in `/home/rogerio/git/mh-pfv/tests/testthat/test-model-strategy.r`:

```r
test_that("new_model_strategy creates valid S3 object", {
    s <- new_model_strategy("linear_regression")
    expect_true(inherits(s, "model_strategy"))
    expect_true(inherits(s, "linear_regression"))
    expect_equal(s$type, "linear_regression")
})

test_that("new_model_strategy validates input", {
    expect_error(new_model_strategy(""))
    expect_error(new_model_strategy(123))
    expect_error(new_model_strategy(c("a", "b")))
})

test_that("default methods raise informative errors", {
    s <- new_model_strategy("nonexistent_model")
    expect_error(fit_model(s, NULL, NULL, NULL), "nao implementado")
    expect_error(predict_model(s, NULL, NULL, NULL, NULL), "nao implementado")
    expect_error(model_metadata(s, NULL), "nao implementado")
})
```

### Integration Tests

None for this ticket.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E01-T006 (snapshot tests must exist as safety net before refactoring)
- **Blocks**: E02-T002

## Effort Estimate

**Points**: 2
**Confidence**: High
