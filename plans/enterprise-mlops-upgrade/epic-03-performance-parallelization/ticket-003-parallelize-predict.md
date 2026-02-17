# E03-T003 Parallelize predict_main Per-Plant Processing

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Replace the `lapply(v_usinas, processar_usina, ...)` call in `predict_main()` with `future.apply::future_lapply()` to process plants in parallel during prediction. This is the primary performance optimization for the production predict pipeline.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/R/predict.r` (replace lapply with future_lapply)
- **Key decisions needed**: Whether `organiza_resultados()` can handle results from parallel workers correctly; how to ensure `pfvIO:::get_model_artifact()` reads are safe under parallel access; whether to collect and report per-plant timing
- **Open questions**: The predict pipeline is more complex than train (two calls to `preenche_geracao_unit`, result combination) -- are there ordering dependencies between plants? Does the `copy()` usage in `processar_usina()` prevent data.table reference-sharing issues?

## Dependencies

- **Blocked By**: E03-T002
- **Blocks**: E03-T005

## Effort Estimate

**Points**: 2
**Confidence**: Low (will be re-estimated during refinement)
