# E03-T003: Update artifact.r + train.r + predict.r + preenchimento-dados-faltantes.r

## Objective

Update the pipeline files to use the new model strategy API: strategy as string in train, remove strategy from predict pipeline entirely, simplify artifact building to receive the classed model object directly.

## Dependencies

- E03-T001 (model-strategy.r rewrite)
- E03-T002 (model-linear-regression.r rewrite)

## Files to Modify

| File                                | Action                                                                                                                     |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `R/artifact.r`                      | Rewrite `build_model_artifact`, delete `build_artifact_metadata`, update `validate_artifact`                               |
| `R/train.r`                         | Change `strategy` default from `linear_regression_strategy()` to `"linear_regression"`, update `build_model_artifact` call |
| `R/predict.r`                       | Remove `strategy` parameter from `predict_main` and `processar_usina`                                                      |
| `R/preenchimento-dados-faltantes.r` | Remove `strategy` parameter from `preenche_geracao_unit`, change `predict_model` call                                      |

## Detailed Implementation

### 1. `R/artifact.r` changes

#### 1a. Delete `build_artifact_metadata`

Remove the entire function `build_artifact_metadata(strategy, model, config)` (lines 27-39). Its logic is inlined into `build_model_artifact`.

#### 1b. Rewrite `build_model_artifact`

Old signature: `build_model_artifact(id_usina, parametros, strategy, config)`
New signature: `build_model_artifact(id_usina, model, config)`

```r
#' Constroi Artefato de Modelo Enriquecido
#'
#' Monta o artefato completo contendo identificador, modelo ajustado com
#' classe e metadados de proveniencia.
#'
#' @param id_usina character escalar, identificador da usina
#' @param model objeto modelo ajustado retornado por [fit_model()], com classe
#'   propria (e.g. `"linear_regression_model"`)
#' @param config lista com a configuracao de treinamento
#'
#' @return lista com tres elementos:
#' \describe{
#'   \item{`id_usina`}{character com o identificador da usina}
#'   \item{`model`}{objeto modelo com classe S3 preservada}
#'   \item{`metadata`}{lista com metadados do modelo, versao do pacote e hash da config}
#' }
#'
#' @export
build_model_artifact <- function(id_usina, model, config) {
    metadata <- model_metadata(model)
    metadata$package_version <- as.character(utils::packageVersion("mhpfv"))
    metadata$config_hash <- digest::digest(
        normalize_config_for_hash(config),
        algo = "sha256"
    )
    list(
        id_usina = id_usina,
        model = model,
        metadata = metadata
    )
}
```

Key changes:

- Second parameter renamed from `parametros` to `model` (the classed object)
- `strategy` parameter removed entirely
- `build_artifact_metadata(strategy, parametros, config)` replaced by inline `model_metadata(model)` + hash
- Artifact stores `$model` (classed object) instead of `$parametros` (bare data.frame)

#### 1c. Update `validate_artifact`

The artifact structure changes from `$parametros` (bare data.frame) to `$model` (classed object). Update validation:

- Replace `check_artifact_parametros` with `check_artifact_model`:
  - Check `"model" %in% names(artifact)` -- required field
  - Check `inherits(artifact$model, "linear_regression_model")` is NOT required (validate_artifact should be model-agnostic)
  - Check that `artifact$model` is a list (all model objects are lists with class)
- Keep `check_artifact_id_usina` unchanged
- Keep `check_artifact_metadata` unchanged (still warns on missing metadata)

```r
check_artifact_model <- function(errors, artifact) {
    if (!"model" %in% names(artifact)) {
        return(c(errors, "Campo obrigatorio ausente: 'model'"))
    }
    if (!is.list(artifact$model)) {
        return(c(errors, "'model' deve ser uma lista com classe S3"))
    }
    errors
}
```

Update `validate_artifact` to call `check_artifact_model` instead of `check_artifact_parametros`.

### 2. `R/train.r` changes

#### 2a. `train_main` signature

Change default from `strategy = linear_regression_strategy()` to `strategy = "linear_regression"`:

```r
train_main <- function(args, strategy = "linear_regression",
    parallel = FALSE, resume = FALSE) {
```

The `strategy` parameter is now a string. All internal usage passes it through to `ajustar_usina` and ultimately to `fit_model(strategy, ...)` which expects a string (per E03-T001).

Update roxygen `@param strategy` documentation: remove reference to `[new_model_strategy()]`, describe as "string escalar identificando o tipo de modelo".

Update roxygen `@seealso`: remove `[linear_regression_strategy()]`, add `[fit_linear_regression()]`.

#### 2b. `ajustar_usina` signature

Change default from `strategy = linear_regression_strategy()` to `strategy = "linear_regression"`:

```r
ajustar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_irrad_prev_filt,
    dt_corte_obs, fonte, fator_tolerancia,
    strategy = "linear_regression", config = list(), ...) {
```

#### 2c. `ajustar_usina` body -- update `build_model_artifact` call

Old call (line 205):

```r
build_model_artifact(iu, regressoes, strategy, config)
```

New call -- `fit_model` now returns a classed model object, and `build_model_artifact` takes `(id_usina, model, config)`:

```r
model <- fit_model(strategy,
    dty = copy(geracao_usina_selec),
    dtx = copy(irrad_prev),
    dty_bruta = geracao_usina_bruta
)

build_model_artifact(iu, model, config)
```

Note: rename the local variable from `regressoes` to `model` to reflect that it is now a classed object, not a bare data.frame.

### 3. `R/predict.r` changes

#### 3a. `predict_main` signature

Remove `strategy` parameter entirely:

```r
predict_main <- function(args, parallel = FALSE, resume = FALSE) {
```

Remove `strategy` from the `apply_args` list that passes arguments to `processar_usina` (line 106):

Old:

```r
apply_args <- list(v_usinas_pending, processar_usina,
    ...,
    strategy = strategy
)
```

New: remove the `strategy = strategy` line.

Update roxygen: remove `@param strategy` and `@seealso` reference to `[linear_regression_strategy()]`.

#### 3b. `processar_usina` signature

Remove `strategy` parameter:

Old:

```r
processar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_mhg,
    dt_mhg_sem_cortes, dt_irrad_prev_filt, dt_corte_obs, fonte,
    fator_tolerancia, artifact_dir,
    strategy = linear_regression_strategy(), ...) {
```

New:

```r
processar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_mhg,
    dt_mhg_sem_cortes, dt_irrad_prev_filt, dt_corte_obs, fonte,
    fator_tolerancia, artifact_dir, ...) {
```

#### 3c. `processar_usina` body -- update `preenche_geracao_unit` calls

Remove `strategy = strategy` from both calls to `preenche_geracao_unit` (lines 275-283 and lines 290-300).

The `model` passed to `preenche_geracao_unit` changes from the raw artifact to `artifact$model` (the classed object):

Old:

```r
model <- pfvIO:::get_model_artifact(iu, artifact_dir)

geracao_usina_preenchida <- preenche_geracao_unit(
    ...,
    model = model,
    strategy = strategy
)
```

New:

```r
artifact <- pfvIO:::get_model_artifact(iu, artifact_dir)

geracao_usina_preenchida <- preenche_geracao_unit(
    ...,
    model = artifact$model
)
```

Note: rename local variable from `model` to `artifact` (since it is the full artifact), and pass `artifact$model` (the classed model object) to `preenche_geracao_unit`.

### 4. `R/preenchimento-dados-faltantes.r` changes

#### 4a. `preenche_geracao_unit` signature

Remove `strategy` parameter:

Old:

```r
preenche_geracao_unit <- function(geracao_usina, irrad_prev, mhg_prev, cortes, limite_dados,
    model, strategy = linear_regression_strategy()) {
```

New:

```r
preenche_geracao_unit <- function(geracao_usina, irrad_prev, mhg_prev, cortes, limite_dados,
    model) {
```

Update roxygen `@param model`: "objeto modelo ajustado com classe S3 (e.g. `linear_regression_model`)". Remove `@param strategy`.

#### 4b. `preenche_geracao_unit` body -- update `predict_model` call

Old (line 51-56):

```r
geracao_usina_completo <- predict_model(strategy,
    model = model$parametros,
    df_ger_usi = copy(geracao_usina),
    df_irrad_prev = copy(irrad_prev),
    lim_dados = limite_dados
)
```

New:

```r
geracao_usina_completo <- predict_model(model,
    df_ger_usi = copy(geracao_usina),
    df_irrad_prev = copy(irrad_prev),
    lim_dados = limite_dados
)
```

Key changes:

- First argument is `model` (classed object), not `strategy`
- `model = model$parametros` removed -- `predict_model.linear_regression_model` accesses `model$parametros` internally
- The `model` parameter received by `preenche_geracao_unit` is now the classed model object (e.g. `linear_regression_model`), not the full artifact

## Acceptance Criteria

1. `build_artifact_metadata` no longer exists in `R/artifact.r`
2. `build_model_artifact(id_usina, model, config)` takes 3 args (no `strategy`), calls `model_metadata(model)` directly
3. Artifact structure is `list(id_usina, model, metadata)` -- `$model` is a classed object, NOT `$parametros` as bare data.frame
4. `validate_artifact` checks for `$model` field (list) instead of `$parametros` (data.frame)
5. `train_main` default `strategy` is `"linear_regression"` (string), not `linear_regression_strategy()`
6. `ajustar_usina` default `strategy` is `"linear_regression"` (string)
7. `ajustar_usina` passes the classed model (returned by `fit_model`) directly to `build_model_artifact`
8. `predict_main` has no `strategy` parameter
9. `processar_usina` has no `strategy` parameter
10. `preenche_geracao_unit` has no `strategy` parameter
11. `preenche_geracao_unit` calls `predict_model(model, ...)` with the classed model as first arg
12. All roxygen2 documentation updated to reflect new signatures

## Scope Boundaries

- Do NOT modify `R/model-strategy.r` or `R/model-linear-regression.r` (done in E03-T001/T002)
- Do NOT modify `NAMESPACE` directly (that is E03-T004)
- Do NOT modify test files (that is E03-T005)
- Do NOT touch `ajusta_regressao_ger_irrad` -- it stays unchanged in `R/train.r`

## Technical Notes

- The artifact structure change (`$parametros` -> `$model`) means existing artifacts on disk will be incompatible. Per the proposal: "No retrocompatibility with old artifacts required (early-stage project)."
- `pfvIO:::get_model_artifact` returns the full artifact. The new code accesses `artifact$model` to get the classed model. If `pfvIO:::get_model_artifact` is changed to return only the model in the future, this code would need updating.
- `normalize_config_for_hash` and `get_config_hash_keys` are unchanged.
