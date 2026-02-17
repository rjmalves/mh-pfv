# E03-T002 Parallelize train_main Per-Plant Processing

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Replace the `lapply(v_usinas, ajustar_usina, ...)` call in `train_main()` with `future.apply::future_lapply()` to process plants in parallel during training. This is the primary performance optimization for the train pipeline, enabling near-linear speedup with the number of available CPU cores.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/R/train.r` (replace lapply with future_lapply), possibly `R/parallel.r` (setup helpers)
- **Key decisions needed**: How to handle the `strategy` parameter in parallel contexts (it must be serializable); whether to use `future.seed = TRUE` for reproducibility; error handling strategy for individual plant failures in parallel mode
- **Open questions**: Are there any shared mutable state issues in `ajustar_usina()` (data.table reference semantics)? Does `pfvIO::write_model_artifact()` support concurrent writes to the same directory? What is the memory overhead per worker?

## Dependencies

- **Blocked By**: E03-T001
- **Blocks**: E03-T003

## Effort Estimate

**Points**: 2
**Confidence**: Low (will be re-estimated during refinement)
