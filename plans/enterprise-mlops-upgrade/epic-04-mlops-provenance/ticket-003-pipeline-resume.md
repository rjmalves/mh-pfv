# E04-T003 Implement Pipeline Resume on Failure

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Implement a checkpoint/resume mechanism so that if the pipeline fails partway through (e.g., on plant 50 of 200), it can be restarted and resume from the last successfully completed plant. This is critical for production reliability, especially with large plant portfolios where a single plant failure should not force reprocessing of all plants.

## Anticipated Scope

- **Files likely to be modified**: New file `R/pipeline.r` for orchestration, `/home/rogerio/git/mh-pfv/R/train.r` and `R/predict.r` (per-plant checkpoint writes), `/home/rogerio/git/mh-pfv/R/cli.r` (resume detection logic)
- **Key decisions needed**: State file format (JSON with per-plant status?); state file location (output directory, artifact directory, or config-specified); how to detect "resume mode" (check for existing state file? explicit CLI flag?); whether to support partial result combination (combine outputs from completed plants even if some failed)
- **Open questions**: How does resume interact with parallel execution (checkpoint must be thread-safe)? Should the state file include a config hash to prevent resuming with different config? How to handle plants that failed (retry vs skip)? Does the data window (janela) need to match for resume to be valid?

## Dependencies

- **Blocked By**: E04-T002
- **Blocks**: None

## Effort Estimate

**Points**: 5
**Confidence**: Low (will be re-estimated during refinement)
