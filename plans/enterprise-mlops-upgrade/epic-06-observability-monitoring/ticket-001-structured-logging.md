# E06-T001 Enhance Structured Logging with Run Context

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Enhance the existing lgr-based logging to include structured context fields (run_id, pipeline_stage, plant_id) in every log message. This enables log aggregation and filtering in production environments and provides traceability from any log line back to the specific run and plant.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/R/logging.r` (enhanced logger with context fields), `/home/rogerio/git/mh-pfv/R/train.r` and `R/predict.r` (add stage context to log calls), `/home/rogerio/git/mh-pfv/R/cli.r` (set run_id context at pipeline start)
- **Key decisions needed**: Whether to use lgr's built-in context (via `lg$with_caller()` or custom fields) or a wrapper function; JSON vs text log format for production; how to propagate run context through parallel workers
- **Open questions**: Does lgr support structured JSON output natively? How should log context work with future/parallel workers (each worker needs its own logger instance)? Should the enhanced logger be opt-in (for backward compatibility with users parsing text logs)?

## Dependencies

- **Blocked By**: E04-T002
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: Low (will be re-estimated during refinement)
