# E06-T002 Add Pipeline Metrics Collection

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Add metrics collection throughout the train and predict pipelines, capturing timing (per-plant, per-stage), data volumes (rows processed, NA rates), and model quality indicators (coefficient summary statistics). Metrics are accumulated during execution and written to a JSON file alongside provenance data.

## Anticipated Scope

- **Files likely to be modified**: New file `R/metrics.r` for metrics collection, `/home/rogerio/git/mh-pfv/R/train.r` and `R/predict.r` (instrument with timing/counting), `/home/rogerio/git/mh-pfv/R/provenance.r` (if created in E04-T002, integrate metrics)
- **Key decisions needed**: Whether metrics are collected in a global environment or passed as a parameter through the pipeline; granularity of timing (per-plant or per-function); how to handle metrics in parallel workers (collect per-worker, merge after)
- **Open questions**: What specific metrics are most useful for ONS operators? Should metrics include memory usage (available via gc() or proc.time())? How should metrics handle pipeline resume (accumulate across resume points)?

## Dependencies

- **Blocked By**: E04-T002
- **Blocks**: E06-T003

## Effort Estimate

**Points**: 3
**Confidence**: Low (will be re-estimated during refinement)
