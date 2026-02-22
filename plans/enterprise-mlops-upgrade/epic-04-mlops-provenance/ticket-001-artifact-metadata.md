# E04-T001 Enrich Model Artifacts with Metadata

## Context

### Background

Model artifacts are currently saved as plain RDS files containing `list(id_usina, parametros)` where `parametros` is a `data.frame` of regression coefficients. There is no metadata attached -- no record of when the model was trained, which package version produced it, what configuration was used, or what training metrics characterize the model. This makes it impossible to audit artifacts or compare model versions.

Epic 02 introduced the `model_metadata()` S3 generic (in `/home/rogerio/git/mh-pfv/R/model-strategy.r`, lines 104-112) with a `linear_regression` implementation (in `/home/rogerio/git/mh-pfv/R/model-linear-regression.r`, lines 82-97) that extracts `type`, `n_slots`, `n_valid_slots`, `mean_coefficient`, and `timestamp` from a fitted model. However, this metadata is never called or persisted -- it exists only as infrastructure waiting to be wired in.

### Relation to Epic

This is the first ticket in Epic 04 (MLOps and Provenance). It establishes the enriched artifact format that all subsequent tickets build upon: run provenance (E04-T002) will attach run-level metadata alongside artifact metadata, pipeline resume (E04-T003) needs to inspect artifact existence, and model comparison (E04-T004) compares metadata fields across artifact versions.

### Current State

**Artifact construction** (`/home/rogerio/git/mh-pfv/R/train.r`, lines 124-131):

```r
# ajustar_usina() returns a plain list:
regressoes <- fit_model(strategy,
    dty = copy(geracao_usina_selec),
    dtx = copy(irrad_prev),
    dty_bruta = geracao_usina_bruta
)
list(id_usina = iu, parametros = regressoes)
```

**Artifact writing** (`/home/rogerio/git/mh-pfv/R/train.r`, lines 89-91):

```r
lapply(seq_along(v_usinas), function(i) {
    write_model_artifact(models[[i]], v_usinas[i], args$artifact)
})
```

`write_model_artifact` is a pfvIO function that calls `saveRDS()`.

**Artifact reading** (`/home/rogerio/git/mh-pfv/R/predict.r`, line 161):

```r
model <- pfvIO:::get_model_artifact(iu, artifact_dir)
```

**Artifact consumption** (`/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`, line 52):

```r
geracao_usina_completo <- predict_model(strategy,
    model = model[[2]],  # <-- hardcoded index, should be model$parametros
    ...
)
```

**model_metadata already exists** (`/home/rogerio/git/mh-pfv/R/model-linear-regression.r`, lines 82-97):

```r
model_metadata.linear_regression <- function(strategy, model, ...) {
    stopifnot(is.data.frame(model), "a" %in% names(model))
    valid_a <- model$a[!is.na(model$a)]
    list(
        type = "linear_regression",
        n_slots = nrow(model),
        n_valid_slots = length(valid_a),
        mean_coefficient = mean(valid_a),
        timestamp = Sys.time()
    )
}
```

**Test generator** (`/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r`, lines 183-196):

```r
gen_model_artifact <- function(id_usina = "USI1") {
    # ... creates data.frame with a, b columns ...
    list(id_usina = id_usina, parametros = parametros)
}
```

## Specification

### Requirements

1. **Enrich artifact structure**: Change the model artifact from `list(id_usina, parametros)` to `list(id_usina, parametros, metadata)` where `metadata` is the output of `model_metadata()` enriched with:
   - `package_version`: character, the mhpfv package version from `packageVersion("mhpfv")`
   - `config_hash`: character, a deterministic hash of the training configuration (use `digest::digest(config, algo = "sha256")` where `config` is a normalized subset of the training args)
   - All fields from `model_metadata()` (type, n_slots, n_valid_slots, mean_coefficient, timestamp)

2. **Create `build_artifact_metadata()` function**: A new helper in a new file `R/artifact.r` that combines `model_metadata()` output with package version and config hash.

3. **Create `validate_artifact()` function**: A validation function in the same `R/artifact.r` file that checks an artifact has the expected structure (id_usina as character, parametros as data.frame with column `a`, metadata as list with required fields). Follows the same error-collection pattern as `validate_input()`.

4. **Fix `model[[2]]` to `model$parametros`**: In `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`, line 52, change `model[[2]]` to `model$parametros` for clarity and forward-compatibility with the enriched artifact.

5. **Backward read compatibility**: `validate_artifact()` must accept artifacts without metadata (old format) and log a warning. The predict pipeline must handle both old artifacts (without metadata) and new artifacts (with metadata) gracefully.

6. **Add `digest` to Imports**: Add the `digest` package to DESCRIPTION Imports.

7. **Update `gen_model_artifact()` test helper**: The helper must generate artifacts in the new format (with metadata).

### Inputs/Props

- `build_artifact_metadata(strategy, model, config)`:
  - `strategy`: S3 `model_strategy` object
  - `model`: fitted model object (e.g., data.frame of coefficients)
  - `config`: list with training configuration (will be hashed)
- `validate_artifact(artifact)`:
  - `artifact`: list, the model artifact to validate

### Outputs/Behavior

- `build_artifact_metadata()` returns a list:
  ```r
  list(
      type = "linear_regression",
      n_slots = 28L,
      n_valid_slots = 26L,
      mean_coefficient = 0.03,
      timestamp = <POSIXct>,
      package_version = "0.1.1",
      config_hash = "sha256:abc123..."
  )
  ```
- `validate_artifact()` returns `invisible(TRUE)` if valid, raises an error with all collected issues otherwise.
- Enriched artifact format:
  ```r
  list(
      id_usina = "BAUFI1",
      parametros = <data.frame with a, b columns>,
      metadata = <list from build_artifact_metadata>
  )
  ```

### Error Handling

- `build_artifact_metadata()`: calls `model_metadata()` which already validates its input; additionally validates that `strategy` is a `model_strategy` and `config` is a list.
- `validate_artifact()`: collects all errors (missing fields, wrong types) before raising, using the same pattern as `validate_input()` in `/home/rogerio/git/mh-pfv/R/validation.r`. For old-format artifacts without `metadata`, log a warning via `lgr` but do not error.
- All error messages in Portuguese, following the project convention.

## Acceptance Criteria

- [ ] Given a fitted model and strategy, when `build_artifact_metadata(strategy, model, config)` is called, then it returns a list containing all fields (type, n_slots, n_valid_slots, mean_coefficient, timestamp, package_version, config_hash)
- [ ] Given the same config, when `build_artifact_metadata()` is called twice, then `config_hash` is identical (deterministic hashing)
- [ ] Given a new-format artifact with id_usina, parametros, and metadata, when `validate_artifact()` is called, then it returns `invisible(TRUE)`
- [ ] Given an old-format artifact with only id_usina and parametros (no metadata), when `validate_artifact()` is called, then it returns `invisible(TRUE)` and logs a warning
- [ ] Given a malformed artifact (missing parametros, or parametros without column `a`), when `validate_artifact()` is called, then it raises an error listing all validation failures
- [ ] Given the updated `train_main()`, when training completes, then each saved artifact contains the `metadata` field
- [ ] Given the updated `preenche_geracao_unit()`, when it accesses model parameters, then it uses `model$parametros` instead of `model[[2]]`
- [ ] Given an old artifact (without metadata) is loaded by `predict_main()`, when prediction runs, then it completes successfully (backward compatibility)
- [ ] Given the `digest` package is added to DESCRIPTION Imports, when `devtools::check()` runs, then no missing dependency warnings occur
- [ ] Given the updated `gen_model_artifact()`, when called, then it returns an artifact with the metadata field

## Implementation Guide

### Suggested Approach

**Step 1: Add `digest` dependency**

In `/home/rogerio/git/mh-pfv/DESCRIPTION`, add `digest (>= 0.6.0)` to Imports.

**Step 2: Create `R/artifact.r`**

```r
#' Constroi Metadados do Artefato de Modelo
#'
#' Combina metadados extraidos da estrategia de modelo com informacoes do
#' pacote e hash da configuracao de treinamento.
#'
#' @param strategy objeto [new_model_strategy()] usado no ajuste
#' @param model modelo ajustado retornado por [fit_model()]
#' @param config lista com a configuracao de treinamento
#'
#' @return lista com metadados completos do artefato
#'
#' @export
build_artifact_metadata <- function(strategy, model, config) {
    stopifnot(inherits(strategy, "model_strategy"))
    stopifnot(is.list(config))

    meta <- model_metadata(strategy, model)
    meta$package_version <- as.character(utils::packageVersion("mhpfv"))
    meta$config_hash <- digest::digest(
        normalize_config_for_hash(config),
        algo = "sha256"
    )

    meta
}

# Normaliza config para hash deterministico: apenas campos relevantes para
# o treinamento, ordenados por nome.
normalize_config_for_hash <- function(config) {
    relevant_keys <- c(
        "janela", "ids_usinas", "ordem_prioridade_fontes",
        "ordem_prioridade_modelosNWP",
        "fator_tolerancia_limite_superior_geracao"
    )
    cfg <- config[intersect(relevant_keys, names(config))]
    cfg[order(names(cfg))]
}

#' Constroi Artefato de Modelo Enriquecido
#'
#' Monta o artefato completo de modelo com metadados.
#'
#' @param id_usina character, identificador da usina
#' @param parametros resultado do ajuste (ex: data.frame de coeficientes)
#' @param strategy objeto [new_model_strategy()]
#' @param config lista com a configuracao de treinamento
#'
#' @return lista com id_usina, parametros e metadata
#'
#' @export
build_model_artifact <- function(id_usina, parametros, strategy, config) {
    metadata <- build_artifact_metadata(strategy, parametros, config)
    list(
        id_usina = id_usina,
        parametros = parametros,
        metadata = metadata
    )
}

#' Valida Artefato de Modelo
#'
#' Verifica a estrutura de um artefato de modelo. Artefatos no formato
#' antigo (sem metadados) sao aceitos com aviso.
#'
#' @param artifact lista, artefato de modelo a ser validado
#'
#' @return `invisible(TRUE)` se o artefato e valido
#'
#' @export
validate_artifact <- function(artifact) {
    errors <- character(0L)

    if (!is.list(artifact)) {
        stop("Artefato deve ser uma lista", call. = FALSE)
    }

    # Campos obrigatorios (presente em ambos os formatos)
    if (!"id_usina" %in% names(artifact)) {
        errors <- c(errors, "Campo obrigatorio ausente: 'id_usina'")
    } else if (!is.character(artifact$id_usina) ||
        length(artifact$id_usina) != 1L) {
        errors <- c(errors, "'id_usina' deve ser character escalar")
    }

    if (!"parametros" %in% names(artifact)) {
        errors <- c(errors, "Campo obrigatorio ausente: 'parametros'")
    } else if (!is.data.frame(artifact$parametros)) {
        errors <- c(errors, "'parametros' deve ser um data.frame")
    } else if (!"a" %in% names(artifact$parametros)) {
        errors <- c(errors, "'parametros' deve conter coluna 'a'")
    }

    if (length(errors) > 0L) {
        msg <- paste0(
            "Validacao do artefato falhou:\n",
            paste0("- ", errors, collapse = "\n")
        )
        stop(msg, call. = FALSE)
    }

    # Metadados opcionais (formato antigo)
    if (!"metadata" %in% names(artifact)) {
        lg <- lgr::get_logger("mhpfv")
        lg$warn(
            "Artefato para usina '%s' sem metadados (formato antigo)",
            artifact$id_usina
        )
    }

    invisible(TRUE)
}
```

**Step 3: Wire metadata into `ajustar_usina()`**

In `/home/rogerio/git/mh-pfv/R/train.r`, modify `ajustar_usina()` to accept `config` and return the enriched artifact via `build_model_artifact()`:

Change line 130:

```r
# BEFORE:
list(id_usina = iu, parametros = regressoes)

# AFTER:
build_model_artifact(iu, regressoes, strategy, config)
```

This requires adding `config` as a parameter to `ajustar_usina()` and passing it from `train_main()` (both in the `lapply` and `future_lapply` calls).

**Step 4: Fix `model[[2]]` to `model$parametros`**

In `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`, line 52:

```r
# BEFORE:
model = model[[2]],

# AFTER:
model = model$parametros,
```

**Step 5: Update `gen_model_artifact()` in test helper**

In `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r`, update `gen_model_artifact()` to include metadata:

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
    metadata <- list(
        type = "linear_regression",
        n_slots = length(hour_names),
        n_valid_slots = length(hour_names),
        mean_coefficient = mean(a_values),
        timestamp = as.POSIXct("2025-07-01 00:00:00", tz = "UTC"),
        package_version = as.character(utils::packageVersion("mhpfv")),
        config_hash = "test-hash-placeholder"
    )
    list(id_usina = id_usina, parametros = parametros, metadata = metadata)
}
```

Also add a helper for old-format artifacts:

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
    list(id_usina = id_usina, parametros = parametros)
}
```

**Step 6: Update NAMESPACE**

Run `devtools::document()` to export `build_artifact_metadata`, `build_model_artifact`, and `validate_artifact`.

### Key Files to Modify

| File                                                          | Change                                                                                       |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `/home/rogerio/git/mh-pfv/DESCRIPTION`                        | Add `digest (>= 0.6.0)` to Imports                                                           |
| `/home/rogerio/git/mh-pfv/R/artifact.r`                       | **NEW FILE** -- `build_artifact_metadata()`, `build_model_artifact()`, `validate_artifact()` |
| `/home/rogerio/git/mh-pfv/R/train.r`                          | Pass `config` to `ajustar_usina()`, use `build_model_artifact()` for return value            |
| `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`  | Line 52: `model[[2]]` to `model$parametros`                                                  |
| `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r` | Update `gen_model_artifact()`, add `gen_model_artifact_legacy()`                             |
| `/home/rogerio/git/mh-pfv/tests/testthat/test-artifact.r`     | **NEW FILE** -- tests for artifact functions                                                 |
| `/home/rogerio/git/mh-pfv/NAMESPACE`                          | Regenerated by `devtools::document()`                                                        |

### Patterns to Follow

- **S3 generics pattern**: Follow `model_metadata()` in `R/model-strategy.r` -- generic in strategy file, implementation in `model-<type>.r`.
- **Validation pattern**: Follow `validate_input()` in `R/validation.r` -- collect all errors in a `character(0L)` vector, then raise a single error with all issues.
- **Test pattern**: Follow `test-model-strategy.r` -- outer `test_that()` asserts function exists, inner blocks test behaviors. Use `gen_config()` from helper-generators for config objects.
- **Error messages in Portuguese**: All `stop()` and `lgr$warn()` messages in Portuguese.
- **Logging via lgr**: Use `lgr::get_logger("mhpfv")` for warnings about legacy artifacts.

### Pitfalls to Avoid

- **Do NOT change `write_model_artifact` in pfvIO**: The pfvIO function uses `saveRDS()` and will happily serialize the enriched list. No changes needed there.
- **Do NOT break existing tests**: After changing `gen_model_artifact()`, grep for all usages. Tests that do `model <- gen_model_artifact()` and then access `model[[1]]` or `model[[2]]` will still work because named list elements are also indexed positionally. But tests that check `length(model) == 2` will break -- find and update those.
- **`pfvIO:::get_model_artifact()` reads via `readRDS()`**: It does NOT strip attributes or list elements. The enriched artifact will be read back identically. No changes needed on the read side.
- **`digest::digest()` must be deterministic**: Ensure the config is normalized (sorted keys, no random elements like timestamps) before hashing. The `normalize_config_for_hash()` helper handles this.
- **Artifact writing remains sequential**: Do not change the `lapply(seq_along(v_usinas), ...)` pattern in `train_main()` lines 89-91. Metadata enrichment happens inside `ajustar_usina()` which runs inside the parallel/sequential dispatch.
- **`config` parameter threading**: `ajustar_usina()` needs the `config` argument. Pass it through both the `lapply` and `future_lapply` calls in `train_main()`. Use `...` if needed to maintain backward compatibility, but explicit named parameter is preferred for clarity.

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-artifact.r`:

1. **`build_artifact_metadata` returns correct structure**: Given `linear_regression_strategy()` and a model from `gen_model_artifact()$parametros`, verify all fields are present and correctly typed.
2. **`build_artifact_metadata` config hash is deterministic**: Call twice with the same config from `gen_config()`, verify hashes are identical.
3. **`build_artifact_metadata` config hash differs with different config**: Call with two different configs, verify hashes differ.
4. **`build_artifact_metadata` validates inputs**: Pass non-strategy, non-list config, verify errors.
5. **`build_model_artifact` returns enriched structure**: Verify the returned list has `id_usina`, `parametros`, and `metadata` fields.
6. **`validate_artifact` accepts new-format artifact**: Pass `gen_model_artifact()`, expect `invisible(TRUE)`.
7. **`validate_artifact` accepts old-format artifact with warning**: Pass `gen_model_artifact_legacy()`, expect `invisible(TRUE)` and a logged warning.
8. **`validate_artifact` rejects malformed artifacts**: Missing `id_usina`, missing `parametros`, `parametros` without column `a` -- each should error with descriptive message.
9. **`model$parametros` access works for both formats**: Verify that `model$parametros` returns the same as `model[[2]]` for both old and new format artifacts.

### Integration Tests

1. **Train pipeline produces enriched artifacts**: Using test data at `tests/testthat/data/` with `janela = list("2025-07-01", "2025-09-30")`, run `train_main()` and verify the saved RDS files contain the `metadata` field. Use `withr::local_tempdir()` for the artifact directory.
2. **Predict pipeline works with enriched artifacts**: Save an enriched artifact via train, then run predict with the same artifact directory. Verify no errors.
3. **Predict pipeline works with legacy artifacts**: Save a legacy artifact (without metadata) to a temp directory, run predict. Verify it completes with a warning.

## Dependencies

- **Blocked By**: E02-T003 (strategy refactor of train -- already completed)
- **Blocks**: E04-T004 (model comparison needs metadata fields)

## Effort Estimate

**Points**: 3
**Confidence**: High
