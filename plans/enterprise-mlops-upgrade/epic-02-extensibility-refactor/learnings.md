# Epic 02: Extensibility Refactor -- Learnings

**Epic**: epic-02-extensibility-refactor
**Date**: 2026-02-17
**Tickets Completed**: 6/6

---

## Patterns Established

- **S3 strategy pattern with dual class**: The `new_model_strategy(type, ...)` constructor creates objects with class `c(type, "model_strategy")`. The first class enables specific dispatch (`fit_model.linear_regression`), while the second class provides a default fallback that raises informative errors (`fit_model.model_strategy`). This two-class pattern is the standard way to implement pluggable strategies in R. Observed in `/home/rogerio/git/mh-pfv/R/model-strategy.r` (lines 22-33).

- **Convenience constructor per strategy type**: Each concrete strategy has a named constructor function (e.g., `linear_regression_strategy()`) that wraps `new_model_strategy("linear_regression")`. This provides a clean public API without exposing the raw constructor and allows future strategies to accept type-specific parameters via `...`. Observed in `/home/rogerio/git/mh-pfv/R/model-linear-regression.r` (lines 22-24).

- **Delegation to existing functions, not duplication**: The concrete strategy methods (`fit_model.linear_regression`, `predict_model.linear_regression`) are thin wrappers that delegate to the original internal functions (`ajusta_regressao_ger_irrad`, `substitui_por_estimativas`). This ensures no algorithm duplication and preserves numerical equivalence by construction. The key insight is the parameter name mapping: `predict_model` accepts `model` but the underlying function expects `regressoes`, handled at the wrapper boundary. Observed in `/home/rogerio/git/mh-pfv/R/model-linear-regression.r` (lines 37-62).

- **Default parameter for backward compatibility**: All refactored functions (`train_main`, `ajustar_usina`, `predict_main`, `processar_usina`, `preenche_geracao_unit`) accept `strategy = linear_regression_strategy()` as a default parameter. This means all call sites that do not pass a strategy continue to work identically, including `cli_main()` which was NOT modified. Observed in `/home/rogerio/git/mh-pfv/R/train.r` (line 44, 69), `/home/rogerio/git/mh-pfv/R/predict.r` (line 47, 124), and `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r` (line 39).

- **Strategy threading through the call chain**: The strategy object is passed as a parameter through the full call chain: `train_main -> ajustar_usina -> fit_model(strategy, ...)` and `predict_main -> processar_usina -> preenche_geracao_unit -> predict_model(strategy, ...)`. Each function in the chain accepts and forwards the strategy without inspecting it. This is the R-idiomatic approach (versus storing state in a global or environment). Observed across `/home/rogerio/git/mh-pfv/R/train.r`, `/home/rogerio/git/mh-pfv/R/predict.r`, and `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`.

- **Validation framework with collected errors**: The `validate_input()` function collects ALL validation failures before raising a single error, rather than failing on the first issue. The implementation separates concerns into three internal check functions (`check_required_columns`, `check_column_types`, `check_key_nas`), each receiving and extending an error vector. This pattern makes the framework easy to extend with new check types. Observed in `/home/rogerio/git/mh-pfv/R/validation.r` (lines 16-36, 126-179).

- **Schema as internal list-of-lists**: Validation schemas are defined as a plain R list inside `get_all_schemas()` rather than external YAML/JSON files. Each schema has `columns` (a named list mapping column name to expected type) and `keys` (character vector of columns that must not contain NA). The `check_type()` function uses `switch()` dispatch for type validation and accepts integer-as-numeric for flexibility. Observed in `/home/rogerio/git/mh-pfv/R/validation.r` (lines 71-122, 181-189).

- **registerS3method for test mock strategy dispatch**: When defining mock S3 methods in test files, simple function definition (e.g., `fit_model.test_strategy <- function(...)`) does NOT enable S3 dispatch through the package namespace. The solution is to call `registerS3method("fit_model", "test_strategy", fit_model.test_strategy, envir = asNamespace("mhpfv"))` at the top level of the test file. This is essential for proving pluggability in tests. Observed in `/home/rogerio/git/mh-pfv/tests/testthat/test-strategy-integration.r` (lines 28-33).

---

## Architectural Decisions

- **Three generics only**: The strategy interface was deliberately kept to exactly 3 generics (`fit_model`, `predict_model`, `model_metadata`) despite potential for more (e.g., `validate_model`, `serialize_model`). The rationale is that adding a new strategy type requires implementing exactly 3 methods, making the barrier to extensibility low. If additional generics are needed in the future, they can be added without breaking existing strategies (new generics get default methods). This decision is encoded in `/home/rogerio/git/mh-pfv/R/model-strategy.r`.

- **Artifact format unchanged**: The model artifact structure `list(id_usina = ..., parametros = ...)` was kept unchanged despite the strategy pattern. The `parametros` element is opaque -- its structure depends on the strategy type. For `linear_regression`, it is a `data.frame` with `a`, `b` columns and `HH:MM` row names. For future strategies, it could be any R object. The `preenche_geracao_unit()` function still accesses `model[[2]]` to extract parametros. This means artifact format is NOT strategy-aware yet -- it will need attention in Epic 04 when metadata/provenance is added.

- **Validation is opt-in, not wired into pipeline**: The `validate_input()` and `validate_all_inputs()` functions are exported but not called anywhere in the production pipeline. This was a deliberate scoping decision: wiring validation into `train_main`/`predict_main` would change the error behavior for all users, which should be a separate ticket. The validation framework exists as a tool that can be called by consumers or integrated later.

- **Portuguese error messages preserved**: All new error messages follow the existing codebase convention of Portuguese-language messages (e.g., "nao implementado para estrategia", "Colunas obrigatorias ausentes", "Schema desconhecido"). This applies to both the strategy interface defaults and the validation framework.

---

## Files and Structures Created

- `/home/rogerio/git/mh-pfv/R/model-strategy.r` -- S3 generics `fit_model`, `predict_model`, `model_metadata` and constructor `new_model_strategy`. This is the abstract interface file that future strategies depend on. 113 lines.
- `/home/rogerio/git/mh-pfv/R/model-linear-regression.r` -- Concrete strategy implementation: `linear_regression_strategy()` constructor and three S3 methods that delegate to `ajusta_regressao_ger_irrad()` and `substitui_por_estimativas()`. 98 lines.
- `/home/rogerio/git/mh-pfv/R/validation.r` -- Input validation framework with `validate_input()`, `validate_all_inputs()`, 5 schemas, and 4 internal check functions. 190 lines.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-model-strategy.r` -- Comprehensive tests for the strategy interface, constructor, default error methods, S3 dispatch proof, linear regression equivalence, and model_metadata. 299 lines.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-validation.r` -- Tests for all 5 schemas (valid/invalid), type checking, NA detection, collected error messages, empty data.table handling, and `validate_all_inputs`. 290 lines.
- `/home/rogerio/git/mh-pfv/tests/testthat/test-strategy-integration.r` -- Mock `test_strategy` with `registerS3method` registration, full lifecycle test (fit -> artifact -> predict), and train_main pluggability proof. 154 lines.
- `/home/rogerio/git/mh-pfv/man/fit_model.Rd`, `predict_model.Rd`, `model_metadata.Rd`, `new_model_strategy.Rd`, `linear_regression_strategy.Rd`, `validate_input.Rd`, `validate_all_inputs.Rd` -- Generated roxygen2 man pages for all new exports.

---

## Conventions Adopted

- **New file naming for strategy pattern**: Strategy interface lives in `model-strategy.r`, concrete implementations in `model-<type>.r` (e.g., `model-linear-regression.r`). Future strategies should follow `model-<type>.r` naming.
- **roxygen2 @rdname for grouping methods**: Concrete strategy methods use `@rdname fit_model` to group their documentation with the generic, while adding `@details ## Metodo <type>` subsections. This keeps man pages consolidated rather than scattered.
- **roxygen2 @seealso uses bracket syntax**: New files use `[function_name()]` rather than `\code{function_name}` for cross-references in @seealso. However, the pre-existing files still use unlinked function names (e.g., `@seealso substitui_por_estimativas`). This inconsistency is inherited from the original codebase.
- **Validation test file mirrors schema structure**: Each schema in `get_all_schemas()` has corresponding positive and negative test cases in `test-validation.r`, maintaining a 1:1 mapping between schemas and test blocks.
- **strategy parameter is always last in signature**: In all refactored functions, `strategy` is the final named parameter (before `...` if present), making it easy to pass as a keyword argument while keeping existing positional arguments stable.

---

## Surprises and Deviations

- **registerS3method was required for test mock dispatch**: The E02-T006 ticket suggested defining mock S3 methods directly in the test file and mentioned "clean up any globally registered S3 methods after tests (use `withr::defer()` if needed)". In practice, simply defining `fit_model.test_strategy <- function(...)` in the test file does not make S3 dispatch work when the generic (`fit_model`) is defined in the mhpfv package namespace. The solution required explicit `registerS3method("fit_model", "test_strategy", fit_model.test_strategy, envir = asNamespace("mhpfv"))` calls. This is a fundamental R packaging constraint: S3 method dispatch searches the namespace of the package that owns the generic, not the caller's environment. The resulting code in `/home/rogerio/git/mh-pfv/tests/testthat/test-strategy-integration.r` (lines 28-33) is more verbose but correct.

- **roxygen2 @seealso links to internal functions generate warnings**: The ticket suggested using `@seealso` to cross-reference functions like `ajusta_regressao_ger_irrad()` and `substitui_por_estimativas()`. However, these functions are internal (not exported), and roxygen2 bracket syntax `[ajusta_regressao_ger_irrad()]` generates R CMD check warnings for undocumented cross-references. The implementation uses bracket syntax for exported functions only and plain text for internal references (e.g., `@seealso ajusta_regressao_ger_irrad` without brackets in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r`).

- **validate_all_inputs does not guard against NULL components**: The E02-T005 ticket's implementation guide showed `if (!is.null(dataset$mhg)) validate_input(...)` guards for optional components. The actual implementation in `/home/rogerio/git/mh-pfv/R/validation.r` (lines 50-58) calls `validate_input` on all components unconditionally, including `mhg` and `mhg_sem_cortes`. This works because in the current codebase `get_dataset()` always returns all 5 components (none are NULL). If pfvIO changes to make components optional, this will need updating.

- **model_metadata uses length() instead of sum() for n_valid_slots**: The ticket suggested `sum(!is.na(model$a))` for counting valid slots. The implementation in `/home/rogerio/git/mh-pfv/R/model-linear-regression.r` (line 93) first filters to `valid_a <- model$a[!is.na(model$a)]` then uses `length(valid_a)`. The result is identical but the intermediate variable makes the code clearer and also reuses `valid_a` for the mean calculation on the next line.

- **processar_usina gained strategy parameter with correct dual preenche_geracao_unit calls**: The ticket warned that `preenche_geracao_unit()` is called twice in `processar_usina()`. Both calls correctly pass `strategy = strategy`. Observed in `/home/rogerio/git/mh-pfv/R/predict.r` (lines 149-157 and 164-174).

---

## Recommendations for Future Epics

- **Epic 03 (Performance)**: When parallelizing the `lapply` calls in `train_main()` (line 52 of `/home/rogerio/git/mh-pfv/R/train.r`) and `predict_main()` (line 55 of `/home/rogerio/git/mh-pfv/R/predict.r`), the `strategy` object is a simple list with a class attribute and carries no mutable state. This means it can be safely shared across parallel workers without serialization issues. However, the `linear_regression_strategy()` default parameter is evaluated per call, so ensure the strategy is created once and passed rather than re-evaluated in each worker. The `test_strategy` mock in `test-strategy-integration.r` can serve as a fast-running strategy for parallel correctness tests.

- **Epic 04 (MLOps/Provenance)**: The `model_metadata()` generic is already in place and returns metadata including `type`, `n_slots`, `n_valid_slots`, `mean_coefficient`, and `timestamp`. Epic 04 should wire this into the artifact structure -- currently the artifact is `list(id_usina, parametros)` and metadata is not stored. A natural extension is `list(id_usina, parametros, metadata = model_metadata(strategy, parametros))`. The `model_metadata` return structure should be standardized with a required schema (similar to the validation schemas in `/home/rogerio/git/mh-pfv/R/validation.r`).

- **Epic 04 (MLOps/Provenance)**: The `validate_input()` framework can serve double duty for validating model artifacts and provenance records. Adding new schemas to `get_all_schemas()` in `/home/rogerio/git/mh-pfv/R/validation.r` is trivial -- just add a new entry to the list with `columns` and `keys`. Epic 04 tickets should plan to reuse this rather than creating a parallel validation system.

- **Epic 03 (Performance)**: The `associa_nwp_usina()` call appears in both `ajustar_usina()` (line 75 of `/home/rogerio/git/mh-pfv/R/train.r`) and `processar_usina()` (line 133 of `/home/rogerio/git/mh-pfv/R/predict.r`). It is called once per plant but operates on ALL plants' NWP data and ALL usinas, making it redundant. For parallelization, this should be hoisted out of the per-plant loop and computed once in `train_main`/`predict_main`, then passed in. This is a pre-optimization step that should happen in Epic 03 before adding `future::future_lapply`.

- **Adding a new strategy**: The extensibility story is now complete. To add a new model type (e.g., `random_forest`), create `R/model-random-forest.r` with `random_forest_strategy()`, `fit_model.random_forest()`, `predict_model.random_forest()`, and `model_metadata.random_forest()`. No existing files need modification. The key constraint is that `fit_model` must return an object compatible with the artifact format (currently the parametros slot of `list(id_usina, parametros)`), and `predict_model` must accept that object and return a data.table with `valor` and `status` columns matching the existing schema.

- **Validation integration into pipeline**: The validation framework was intentionally left opt-in. A natural follow-up ticket (in any future epic) would add `validate_all_inputs(dataset, dt_usinas)` calls at the top of `train_main()` and `predict_main()`, guarded by a config flag (e.g., `args$validate_inputs` defaulting to `FALSE`) for backward compatibility. The existing tests in `/home/rogerio/git/mh-pfv/tests/testthat/test-validation.r` (line 218-230) already prove that the real test dataset passes all validations.

---

## Technical Debt Identified

- **model[[2]] hardcoded index for parametros**: The `preenche_geracao_unit()` function accesses `model[[2]]` to get the parametros data.frame from the artifact list. This numeric indexing is fragile -- if the artifact structure changes (e.g., by adding metadata), the index breaks. Should be changed to `model$parametros` or `model[["parametros"]]`. Located in `/home/rogerio/git/mh-pfv/R/preenchimento-dados-faltantes.r` (line 52).

- **pfvIO:::get_model_artifact triple-colon access persists**: The predict pipeline still uses `pfvIO:::get_model_artifact(iu, artifact_dir)` in `/home/rogerio/git/mh-pfv/R/predict.r` (line 147). This was identified as technical debt in Epic 01 and remains unaddressed. The strategy refactor did not change this call because the artifact loading is separate from the strategy pattern.

- **parsearg_janela S3 method registration bug persists**: The NAMESPACE is still missing `S3method(parsearg_janela, character)`. This pre-existing bug was documented in Epic 01 learnings and remains.

- **Validation schemas may drift from pfvIO**: The column schemas in `get_all_schemas()` are hardcoded in mhpfv. If pfvIO changes its output format (renames columns, adds required columns), the validation schemas become stale silently. There is no mechanism to keep them in sync. A future improvement would be to have pfvIO export its own schemas.

- **@seealso inconsistency between old and new files**: New files use `[function()]` bracket syntax for exported functions in roxygen2. Old files use plain function names without brackets. This is cosmetic but creates inconsistent man page rendering.
