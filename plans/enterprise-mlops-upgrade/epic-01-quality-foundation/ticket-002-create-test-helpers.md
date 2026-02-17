# E01-T002 Create Test Helper Module with Synthetic Data Generators

## Context

### Background

The mhpfv package tests currently create test data inline within each `test_that()` block. This leads to duplicated data construction code across test files and makes it difficult to create standardized test scenarios. A shared test helper module with factory functions for synthetic data will accelerate test writing in this epic and all future epics.

### Relation to Epic

This ticket creates shared infrastructure used by E01-T004 (integration test for train), E01-T005 (integration test for predict), E01-T006 (snapshot tests), and E01-T007 (expanded unit tests). It is a foundational utility ticket.

### Current State

- Test data is constructed inline in each test file using `data.table()` constructors
- The test dataset at `/home/rogerio/git/mh-pfv/tests/testthat/data/` contains a 2-plant dataset with CSV and Parquet files
- There is one helper function `gen_config()` in `test-config-file.r` that generates a default config list, but it is local to that test file
- No shared `helper-*.r` or `setup.r` file exists in the `tests/testthat/` directory

## Specification

### Requirements

1. Create a file `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r` containing factory functions for test data
2. The file must be auto-loaded by testthat (files named `helper-*.r` are sourced before tests)
3. Factory functions must produce data.tables matching the exact column schemas used by mhpfv internal functions
4. Each factory function must accept optional parameters to control size, date range, plant IDs, and data patterns (normal, all-NA, frozen values, etc.)

### Inputs/Props

Factory functions to create:

| Function                                             | Returns    | Purpose                                                                                                       |
| ---------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------- |
| `gen_config(mode, ...)`                              | Named list | Valid JSONC-equivalent config; move from test-config-file.r                                                   |
| `gen_usinas(n, ids)`                                 | data.table | Plant metadata (id_usina, latitude, longitude, capacidade_instalada_MW, data_inicio_operacao_comercial)       |
| `gen_geracao_observada(ids, datas, fontes, pattern)` | data.table | Observed generation with columns (id_fonte_observacao, id_usina, data_hora_observacao, valor)                 |
| `gen_irradiancia_prevista(ids, datas, modelo_nwp)`   | data.table | NWP irradiance with columns (id_modelo_nwp, latitude, longitude, data_hora_rodada, data_hora_previsao, valor) |
| `gen_corte_observado(ids, datas, frac_corte)`        | data.table | Cut observations with columns (id_usina, data_hora_observacao, valor) where valor in {0, 1}                   |
| `gen_mhg(ids, datas)`                                | data.table | Historical best generation with columns (id_fonte_observacao, id_usina, data_hora_observacao, valor, status)  |
| `gen_model_artifact(id_usina)`                       | list       | Model artifact matching format: list(id_usina, parametros = data.frame(a, b, row.names))                      |

### Outputs/Behavior

- Each function returns a well-formed data.table (or list for config/artifact) that can be passed directly to mhpfv internal functions
- The `pattern` parameter in `gen_geracao_observada` must support at least: `"normal"` (realistic solar curve), `"frozen"` (constant values to trigger frozen detection), `"missing"` (sparse NAs), `"all_na"` (all NA)
- Date sequences default to 30-minute intervals matching the package convention
- Plant coordinates default to Brazilian solar belt (-20 to -25 latitude, -45 to -50 longitude)

### Error Handling

- Factory functions must validate that `ids` is a character vector
- Factory functions must stop with an informative error if `pattern` is not one of the supported values

## Acceptance Criteria

- [ ] Given the file `tests/testthat/helper-generators.r` exists, when testthat loads, then all factory functions are available in the test environment
- [ ] Given `gen_config()` is called with no arguments, when the result is passed to `valida_nomes_config()`, then validation passes
- [ ] Given `gen_usinas(n = 3)` is called, when the result is inspected, then it is a data.table with 3 rows and columns (id_usina, latitude, longitude, capacidade_instalada_MW, data_inicio_operacao_comercial)
- [ ] Given `gen_geracao_observada(ids = "U1", datas = seq(as.POSIXct("2025-01-01"), by = "30 min", length.out = 48), fontes = c("PI"), pattern = "normal")`, when the result is inspected, then it has 48 rows with realistic solar-curve values (zero at night, positive during day)
- [ ] Given `gen_geracao_observada(..., pattern = "frozen")`, when passed to `checa_valores_congelados()`, then frozen values are detected
- [ ] Given `gen_model_artifact("U1")`, when the result is inspected, then it is a list with `[[1]] == "U1"` and `[[2]]` is a data.frame with columns `a` and `b` and row names matching half-hour slots from "05:00" to "18:30"
- [ ] Given the existing `gen_config()` function in `test-config-file.r`, when it is moved to `helper-generators.r`, then `test-config-file.r` still passes all tests
- [ ] Given `R CMD check`, when run, then it passes with no new warnings

## Implementation Guide

### Suggested Approach

1. Create `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r`
2. Move `gen_config()` from `test-config-file.r` to `helper-generators.r` and update `test-config-file.r` to remove the local definition
3. Implement each factory function following the column schemas found in the existing source code:
   - For `gen_usinas`: Reference column names used in `ajustar_usina()` and `processar_usina()` in `/home/rogerio/git/mh-pfv/R/train.r` and `/home/rogerio/git/mh-pfv/R/predict.r`
   - For `gen_geracao_observada`: Reference columns used in `consiste_geracao_unit()` in `/home/rogerio/git/mh-pfv/R/consistencia-dados.r`
   - For `gen_irradiancia_prevista`: Reference columns used in `associa_nwp_usina()` in `/home/rogerio/git/mh-pfv/R/utils.r`
   - For `gen_corte_observado`: Reference columns used in `aplica_cortes_em_geracao()` in `/home/rogerio/git/mh-pfv/R/consistencia-dados.r`
   - For `gen_mhg`: Reference columns used in `combina_dados_tempo()` in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`
   - For `gen_model_artifact`: Reference the artifact structure produced by `ajustar_usina()` in `/home/rogerio/git/mh-pfv/R/train.r` (list with id_usina and parametros data.frame)
4. For the "normal" pattern in `gen_geracao_observada`, use a simple sine curve scaled by capacidade_instalada_MW, with zero values between 19:00-04:30
5. Run all existing tests to confirm nothing is broken

### Key Files to Modify

- **Create**: `/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r`
- **Modify**: `/home/rogerio/git/mh-pfv/tests/testthat/test-config-file.r` (remove local `gen_config()` definition)

### Patterns to Follow

- Use `data.table::data.table()` for all data construction (matching codebase convention)
- Use `as.POSIXct()` with explicit timezone for all datetime columns
- Follow the existing test data column naming exactly (Portuguese names like `id_usina`, `data_hora_observacao`, `valor`, `id_fonte_observacao`)
- Document each factory function with a brief comment block explaining parameters and return value

### Pitfalls to Avoid

- Do not add `helper-generators.r` to the `R/` directory -- it belongs in `tests/testthat/` only
- Do not use `library()` calls in the helper file -- testthat already loads the package
- Ensure all POSIXct timestamps use UTC timezone to match the production code
- Do not use `set.seed()` globally -- if randomness is needed, use it locally within the factory function with a default seed parameter
- The `gen_config()` function must return a plain list (not a data.table) with exactly the keys expected by `config_names()` in `/home/rogerio/git/mh-pfv/R/config-file.r`

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-helper-generators.r` with tests for each factory function:

- Verify column names match expected schemas
- Verify data types (numeric, POSIXct, character) are correct
- Verify `pattern` parameter produces expected characteristics
- Verify `gen_config()` passes `valida_nomes_config()` and `valida_tipos_config()`

### Integration Tests

None for this ticket.

### E2E Tests

None.

## Dependencies

- **Blocked By**: None
- **Blocks**: E01-T004, E01-T005, E01-T006, E01-T007

## Effort Estimate

**Points**: 2
**Confidence**: High
