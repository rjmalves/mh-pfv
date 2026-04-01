# Master Plan: Simplification Refactor

## Goal

Address all three findings from `proposal-simplification.md`:

1. **Per-plant resilience** -- wrap plant processing in `tryCatch` so a single plant failure does not abort the entire pipeline.
2. **Provenance/metrics as environments** -- replace copy-on-modify lists with R environments for in-place mutation, eliminating `<<-` from pipelines.
3. **Model strategy simplification** -- replace the stateless `model_strategy` S3 class with string-based dispatch for `fit_model` and model-class-based dispatch for `predict_model`/`model_metadata`.

## Scope

- R package `mhpfv` -- source under `R/`, tests under `tests/testthat/`, `NAMESPACE`
- No external API changes beyond what is documented in the proposal
- No retrocompatibility with old artifacts required (early-stage project)
- Each epic maps to one independent PR

## Architecture Decisions

| Decision                                                 | Rationale                                                                                                                                                                                                        |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Execute resilience before provenance refactor            | Resilience fixes a real bug (one plant kills pipeline). The provenance refactor touches the same code; doing resilience first means the tryCatch + sentinel are already in place when we switch to environments. |
| Use `plant_error` sentinel class                         | A dedicated S3 class avoids mixing error information with normal results. `inherits(x, "plant_error")` is unambiguous.                                                                                           |
| Environments for provenance and metrics                  | Eliminates `<<-` anti-pattern, O(1) mutation per plant (no copy-on-modify), cleaner code. Serialization handled via `prov_as_list()` at write points.                                                            |
| `fit_model` as regular function with name-based dispatch | The input is a string, not an object -- S3 dispatch on a string is semantically wrong. `get0(fn_name, envir = ns)` scoped to namespace is explicit and safe.                                                     |
| `predict_model`/`model_metadata` dispatch on model class | The model object carries its own class. S3 dispatch on the model is the natural R idiom.                                                                                                                         |
| Keep `strategy` parameter in train pipeline as string    | Train needs to know which model to fit. A string is sufficient.                                                                                                                                                  |
| Remove `strategy` from predict pipeline entirely         | The loaded artifact already carries a classed model. No external dispatch key needed.                                                                                                                            |

## Epic Breakdown

| Epic | Name                             | Tickets | Detail Level |
| ---- | -------------------------------- | ------- | ------------ |
| 01   | Per-Plant Resilience             | 4       | Detailed     |
| 02   | Environment Provenance & Metrics | 4       | Detailed     |
| 03   | Model Strategy Simplification    | 5       | Outline      |

## Sequencing

```
Epic 01 (resilience) --> Epic 02 (environments) --> Epic 03 (model strategy)
```

Epic 01 must complete before Epic 02 because both modify the same `lapply` loops in `train.r` and `predict.r`. Epic 02 must complete before Epic 03 because Epic 03 changes public function signatures (`predict_model`, `build_model_artifact`) and is safest to execute after the internal representation is stable.

## Dependency Graph

```
E01-T001 (plant_error sentinel)
  |
  +--> E01-T002 (train resilience) --+
  |                                   |
  +--> E01-T003 (predict resilience) -+--> E01-T004 (resilience tests)
                                             |
                                             v
                                      E02-T001 (provenance as env)
                                        |
                                        +--> E02-T002 (metrics as env)
                                        |      |
                                        +------+--> E02-T003 (train/predict remove <<-)
                                                       |
                                                       +--> E02-T004 (env tests)
                                                              |
                                                              v
                                                       E03-T001 (model-strategy.r rewrite)
                                                         |
                                                         +--> E03-T002 (model-linear-regression.r rewrite)
                                                         |      |
                                                         +------+--> E03-T003 (artifact.r + train/predict)
                                                                       |
                                                                       +--> E03-T004 (NAMESPACE + cli.r)
                                                                       |
                                                                       +--> E03-T005 (tests rewrite)
```
