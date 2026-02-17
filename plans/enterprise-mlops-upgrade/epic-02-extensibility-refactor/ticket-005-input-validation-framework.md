# E02-T005 Add Input Data Validation Framework

## Context

### Background

The mhpfv package currently validates only the config file structure (via `valida_nomes_config()` and `valida_tipos_config()`). There is no systematic validation of input data.tables before they enter the processing pipeline. Malformed data (wrong column types, missing columns, unexpected NAs in key columns) can cause cryptic errors deep in the pipeline. A lightweight validation framework will catch data issues early with clear error messages.

### Relation to Epic

This ticket is independent of the model strategy tickets (E02-T001 through E02-T004) and can be developed in parallel. It depends only on E01-T002 (test helpers) for testing. It is blocked by E02-T006 (comprehensive tests).

### Current State

- Config validation exists in `/home/rogerio/git/mh-pfv/R/config-file.r`
- Output validation exists in `/home/rogerio/git/mh-pfv/R/escrita.r` via `pfvIO:::valida_dado_singular_completo()`
- No input data.table validation exists between data loading and processing
- pfvIO validates data on write but not on read

## Specification

### Requirements

1. Create `/home/rogerio/git/mh-pfv/R/validation.r` with validation functions for input data.tables
2. Implement a `validate_input(dt, schema_name)` function that checks:
   - Required columns are present
   - Column types match expected types
   - Key columns (id_usina, datetime columns) have no unexpected NAs
3. Define schemas for each input type: `geracao_observada`, `irradiancia_prevista`, `corte_observado`, `usinas`
4. Validation errors must be informative: which schema, which check failed, which columns
5. Validation must be opt-in (called explicitly) -- do NOT add it to existing pipeline functions in this ticket
6. Add a `validate_all_inputs(dataset, usinas)` convenience function that validates the full dataset returned by `get_dataset()`

### Inputs/Props

**`validate_input(dt, schema_name)`**:

- `dt`: data.table to validate
- `schema_name`: one of `"geracao_observada"`, `"irradiancia_prevista"`, `"corte_observado"`, `"usinas"`, `"melhor_historico_geracao"`

**Schema definitions** (derived from existing code usage):

| Schema                   | Required Columns                                                                                                                         | Key Columns (no NA allowed)    |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| geracao_observada        | id_fonte_observacao (char), id_usina (char), data_hora_observacao (POSIXct), valor (numeric)                                             | id_usina, data_hora_observacao |
| irradiancia_prevista     | id_modelo_nwp (char), latitude (numeric), longitude (numeric), data_hora_rodada (POSIXct), data_hora_previsao (POSIXct), valor (numeric) | data_hora_previsao             |
| corte_observado          | id_usina (char), data_hora_observacao (POSIXct), valor (numeric)                                                                         | id_usina, data_hora_observacao |
| usinas                   | id_usina (char), latitude (numeric), longitude (numeric), capacidade_instalada_MW (numeric), data_inicio_operacao_comercial (POSIXct)    | id_usina                       |
| melhor_historico_geracao | id_fonte_observacao (char), id_usina (char), data_hora_observacao (POSIXct), valor (numeric), status (integer/numeric)                   | id_usina, data_hora_observacao |

### Outputs/Behavior

- `validate_input()` returns `invisible(TRUE)` on success
- On failure, raises `stop()` with a message listing all validation failures (not just the first one)
- `validate_all_inputs()` validates each component of the dataset list and the usinas data.table

### Error Handling

- Unknown schema_name: `stop("Schema desconhecido: '...' ")`
- Multiple validation failures are collected and reported together in a single error message
- Empty data.tables pass validation (they have correct structure even with 0 rows)

## Acceptance Criteria

- [ ] Given a valid geracao_observada data.table, when `validate_input(dt, "geracao_observada")` is called, then it returns TRUE
- [ ] Given a data.table missing the `valor` column, when `validate_input(dt, "geracao_observada")` is called, then it raises an error mentioning "valor"
- [ ] Given a data.table with character `valor` instead of numeric, when validated, then it raises a type error
- [ ] Given a data.table with NA in `id_usina`, when validated against a schema where id_usina is a key column, then it raises an error
- [ ] Given the test dataset loaded via pfvIO, when `validate_all_inputs()` is called, then all validations pass
- [ ] Given an empty data.table with correct column names and types, when validated, then it passes
- [ ] Given `R CMD check` and `lintr`, when run, then they pass with no new warnings

## Implementation Guide

### Suggested Approach

Create `/home/rogerio/git/mh-pfv/R/validation.r`:

```r
#' Valida data.table de Entrada Contra um Schema
#'
#' @param dt data.table a ser validada
#' @param schema_name nome do schema de validacao
#'
#' @return TRUE invisivel se validacao for bem-sucedida; erro do contrario
#'
#' @export
validate_input <- function(dt, schema_name) {
    schema <- get_schema(schema_name)
    errors <- character(0)

    # Check required columns
    missing_cols <- setdiff(schema$columns, names(dt))
    if (length(missing_cols) > 0) {
        errors <- c(errors, paste0(
            "Colunas faltantes: ", paste(missing_cols, collapse = ", ")
        ))
    }

    # Check column types (only for columns that exist)
    present_cols <- intersect(schema$columns, names(dt))
    for (col in present_cols) {
        expected_type <- schema$types[[col]]
        actual <- dt[[col]]
        if (!check_type(actual, expected_type)) {
            errors <- c(errors, paste0(
                "Coluna '", col, "': esperado ", expected_type,
                ", encontrado ", class(actual)[1]
            ))
        }
    }

    # Check key columns for NAs (only if column exists and dt has rows)
    if (nrow(dt) > 0) {
        for (col in intersect(schema$key_columns, names(dt))) {
            n_na <- sum(is.na(dt[[col]]))
            if (n_na > 0) {
                errors <- c(errors, paste0(
                    "Coluna chave '", col, "' contem ", n_na, " valor(es) NA"
                ))
            }
        }
    }

    if (length(errors) > 0) {
        msg <- paste0(
            "Validacao falhou para schema '", schema_name, "':\n",
            paste0("  - ", errors, collapse = "\n")
        )
        stop(msg, call. = FALSE)
    }

    invisible(TRUE)
}

# Internal schema definitions
get_schema <- function(name) {
    schemas <- list(
        geracao_observada = list(
            columns = c("id_fonte_observacao", "id_usina", "data_hora_observacao", "valor"),
            types = list(
                id_fonte_observacao = "character",
                id_usina = "character",
                data_hora_observacao = "POSIXct",
                valor = "numeric"
            ),
            key_columns = c("id_usina", "data_hora_observacao")
        ),
        # ... other schemas ...
    )

    if (!name %in% names(schemas)) {
        stop(paste0("Schema desconhecido: '", name, "'"), call. = FALSE)
    }
    schemas[[name]]
}

check_type <- function(x, expected) {
    if (expected == "numeric") return(is.numeric(x))
    if (expected == "character") return(is.character(x))
    if (expected == "POSIXct") return(inherits(x, "POSIXct"))
    if (expected == "integer") return(is.integer(x) || is.numeric(x))
    FALSE
}
```

Implement all 5 schemas from the specification table. Then add:

```r
#' Valida Todos os Inputs do Dataset
#'
#' @param dataset lista nomeada retornada por get_dataset()
#' @param dt_usinas data.table de usinas
#'
#' @return TRUE invisivel se todas as validacoes passarem
#'
#' @export
validate_all_inputs <- function(dataset, dt_usinas) {
    validate_input(dt_usinas, "usinas")
    validate_input(dataset$ger_obs, "geracao_observada")
    validate_input(dataset$irrad_prev, "irradiancia_prevista")
    validate_input(dataset$corte, "corte_observado")
    if (!is.null(dataset$mhg)) validate_input(dataset$mhg, "melhor_historico_geracao")
    if (!is.null(dataset$mhg_sem_cortes)) validate_input(dataset$mhg_sem_cortes, "melhor_historico_geracao")
    invisible(TRUE)
}
```

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/R/validation.r`
- **Auto-generated**: NAMESPACE, man pages

### Patterns to Follow

- Follow the config validation pattern in `config-file.r` (collect errors, report all at once)
- Use `call. = FALSE` in `stop()` for cleaner error messages
- Keep schemas as a simple list structure (no external files)

### Pitfalls to Avoid

- Do NOT add validation calls to existing pipeline functions in this ticket -- that is for future tickets
- The `irradiancia_prevista` schema may not have `id_usina` in the raw data (it gets added by `associa_nwp_usina()`) -- the schema should reflect the raw input format
- The `valor` column in `corte_observado` contains 0/1 integers but is stored as numeric -- accept both integer and numeric
- Some data.tables loaded by pfvIO may have additional columns beyond the schema -- validation should not fail on extra columns

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-validation.r`:

- Test each schema with valid data (using generators from helper-generators.r)
- Test missing column detection
- Test wrong type detection
- Test NA in key column detection
- Test unknown schema error
- Test empty data.table passes
- Test `validate_all_inputs()` with the test dataset

### Integration Tests

None for this ticket.

### E2E Tests

None.

## Dependencies

- **Blocked By**: E01-T002
- **Blocks**: E02-T006

## Effort Estimate

**Points**: 3
**Confidence**: High
