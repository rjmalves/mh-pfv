# E02-T003 Refactor train.r to Use Model Strategy

## Context

### Background

With the S3 model strategy interface (E02-T001) and linear regression implementation (E02-T002) in place, `train.r` must be refactored to use the strategy pattern instead of calling `ajusta_regressao_ger_irrad()` directly. This enables future model types to be used for training without modifying `train.r`.

### Relation to Epic

Depends on E02-T002 (linear regression strategy). Blocks E02-T004 (predict refactor). The refactoring must be numerically equivalent, verified by snapshot tests from E01-T006.

### Current State

In `/home/rogerio/git/mh-pfv/R/train.r`, the `ajustar_usina()` function (line 104) calls:

```r
regressoes <- ajusta_regressao_ger_irrad(
    dty = copy(geracao_usina_selec),
    dtx = copy(irrad_prev),
    dty_bruta = geracao_usina_bruta
)
```

The function `train_main()` (line 48) calls `ajustar_usina()` via `lapply`. The artifact is `list(id_usina, parametros = regressoes)`.

## Specification

### Requirements

1. Modify `train_main()` to accept an optional `strategy` parameter (default: `linear_regression_strategy()`)
2. Pass the strategy through to `ajustar_usina()`
3. Modify `ajustar_usina()` to accept a `strategy` parameter and call `fit_model(strategy, ...)` instead of `ajusta_regressao_ger_irrad()` directly
4. The artifact format must remain `list(id_usina, parametros)` -- do NOT change the artifact structure
5. The default behavior (no strategy argument) must be identical to the current behavior
6. All existing tests must pass unchanged
7. All snapshot tests must pass (numerical equivalence)

### Inputs/Props

- `strategy` parameter: S3 object of class `model_strategy` (default: `linear_regression_strategy()`)
- All other inputs unchanged

### Outputs/Behavior

- When called without `strategy`, behavior is identical to current
- When called with `linear_regression_strategy()`, behavior is identical to current
- Artifacts are identical in format and content

### Error Handling

- If `strategy` is not a `model_strategy` object, raise `stop("strategy deve ser um objeto model_strategy")`

## Acceptance Criteria

- [ ] Given `train_main(config)` called without strategy, when run, then it produces identical artifacts to the current version
- [ ] Given `train_main(config, strategy = linear_regression_strategy())`, when run, then it produces identical artifacts
- [ ] Given all existing tests, when run, then they pass unchanged
- [ ] Given snapshot tests from E01-T006, when run, then they pass (numerical equivalence)
- [ ] Given `R CMD check` and `lintr`, when run, then they pass with no new warnings
- [ ] Given `ajustar_usina()`, when its signature is inspected, then it includes `strategy` parameter

## Implementation Guide

### Suggested Approach

1. Modify `train_main()` in `/home/rogerio/git/mh-pfv/R/train.r`:

```r
#' @param strategy objeto de estrategia de modelo (padrao: regressao linear)
#' @export
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
        iu <- v_usinas[i]
        model <- models[[i]]
        write_model_artifact(model, iu, args$artifact)
    })
}
```

2. Modify `ajustar_usina()` to accept and use strategy:

```r
ajustar_usina <- function(
    iu, dt_usinas, dt_ger_obs,
    dt_irrad_prev, dt_corte_obs, fonte, fator_tolerancia,
    strategy = linear_regression_strategy()
) {
    # ... existing data preparation code unchanged ...

    # Replace direct call with strategy dispatch
    regressoes <- fit_model(strategy,
        dty = copy(geracao_usina_selec),
        dtx = copy(irrad_prev),
        dty_bruta = geracao_usina_bruta
    )

    return(
        list(
            id_usina = iu,
            parametros = regressoes
        )
    )
}
```

3. Run all tests including snapshots
4. Run `devtools::document()`, `devtools::check()`, `lintr::lint_package()`

### Key Files to Modify

- **Modify**: `/home/rogerio/git/mh-pfv/R/train.r` (add strategy parameter to train_main and ajustar_usina, replace direct call)
- **Auto-generated**: `/home/rogerio/git/mh-pfv/man/train_main.Rd` (updated roxygen2 docs)

### Patterns to Follow

- Default parameter value `strategy = linear_regression_strategy()` ensures backward compatibility
- Pass strategy through the call chain (train_main -> ajustar_usina -> fit_model)
- Keep all data preparation code in `ajustar_usina()` unchanged -- only the model fitting call changes

### Pitfalls to Avoid

- Do NOT remove `ajusta_regressao_ger_irrad()` from train.r -- it is still the underlying implementation called by `fit_model.linear_regression()`
- Do NOT change the artifact structure -- it must remain `list(id_usina, parametros)`
- The `lapply` call in `train_main` passes named arguments -- add `strategy = strategy` as the last named argument
- Ensure the `copy()` calls on data.tables are preserved (they prevent mutation of the caller's data)

## Testing Requirements

### Unit Tests

Existing tests in `test-train.r` must pass unchanged. Add one new test:

```r
test_that("train_main accepts custom strategy", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(mode = "train")
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    strategy <- linear_regression_strategy()
    expect_no_error(train_main(config, strategy = strategy))
})
```

### Integration Tests

Existing integration tests from E01-T004 must pass unchanged.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E02-T002
- **Blocks**: E02-T004

## Effort Estimate

**Points**: 2
**Confidence**: High
