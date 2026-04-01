# Epic 03: Model Strategy Simplification

## Objective

Eliminate the `model_strategy` S3 class. `fit_model` becomes a regular function dispatching by string convention (`fit_<strategy>`). `predict_model` and `model_metadata` become S3 generics dispatching on the **model** class instead of the strategy class. The `strategy` parameter is removed from the predict pipeline entirely.

## Context

After Epics 01 and 02, the pipelines have resilience and clean environment-based provenance/metrics. This epic changes public function signatures and is the largest refactor. It touches more files and changes the NAMESPACE.

## Tickets

| ID       | Name                                              | Description                                                                                           |
| -------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| E03-T001 | [OUTLINE] Rewrite model-strategy.r                | Convert `fit_model` to regular function; change `predict_model`/`model_metadata` to dispatch on model |
| E03-T002 | [OUTLINE] Rewrite model-linear-regression.r       | `fit_linear_regression` returns classed object; methods dispatch on `linear_regression_model`         |
| E03-T003 | [OUTLINE] Update artifact.r + train.r + predict.r | Simplify `build_model_artifact`; strategy as string in train; remove strategy from predict            |
| E03-T004 | [OUTLINE] Update NAMESPACE + cli.r                | Remove old exports/S3methods, add new ones; simplify cli                                              |
| E03-T005 | [OUTLINE] Rewrite tests                           | Update all strategy and integration tests for new API                                                 |

## Open Questions (to resolve before execution)

1. Should `fit_model` be exported? The proposal says yes. But callers are internal (`ajustar_usina`). Decision: export for testing convenience.
2. Should `fit_linear_regression` be exported? The proposal says yes. Useful for direct testing.
3. Should we keep `validate_artifact` or update it for the new model structure? The current validation checks `$parametros` as `data.frame` -- with the new structure, `$model` is a classed list. Decision deferred.
4. The proposal mentions no retrocompatibility with old artifacts. Confirm this assumption still holds.
