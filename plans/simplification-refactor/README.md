# Simplification Refactor

Addresses the three findings from `proposal-simplification.md`:

1. Per-plant resilience (tryCatch in processing loops)
2. Provenance/metrics as R environments (eliminate <<-)
3. Model strategy simplification (string dispatch, model-class S3)

## Execution Order

```
Epic 01 --> Epic 02 --> Epic 03
```

## Progress

| ID       | Epic                              | Ticket                            | Status    | Readiness | Agent       |
| -------- | --------------------------------- | --------------------------------- | --------- | --------- | ----------- |
| E01-T001 | 01-per-plant-resilience           | Plant Error Sentinel              | completed | 0.94      | r-developer |
| E01-T002 | 01-per-plant-resilience           | Train Pipeline Resilience         | completed | 0.90      | r-developer |
| E01-T003 | 01-per-plant-resilience           | Predict Pipeline Resilience       | completed | 0.88      | r-developer |
| E01-T004 | 01-per-plant-resilience           | Resilience Integration Tests      | completed | 0.86      | r-developer |
| E02-T001 | 02-environment-provenance-metrics | Provenance as Environment         | pending   | 0.92      | r-developer |
| E02-T002 | 02-environment-provenance-metrics | Metrics as Environment            | pending   | 0.90      | r-developer |
| E02-T003 | 02-environment-provenance-metrics | Remove <<- from Pipelines         | pending   | 0.88      | r-developer |
| E02-T004 | 02-environment-provenance-metrics | Environment Adaptation Tests      | pending   | 0.86      | r-developer |
| E03-T001 | 03-model-strategy-simplification  | Rewrite model-strategy.r          | pending   | --        | r-developer |
| E03-T002 | 03-model-strategy-simplification  | Rewrite model-linear-regression.r | pending   | --        | r-developer |
| E03-T003 | 03-model-strategy-simplification  | Update artifact + train + predict | pending   | --        | r-developer |
| E03-T004 | 03-model-strategy-simplification  | Update NAMESPACE + cli.r          | pending   | --        | r-developer |
| E03-T005 | 03-model-strategy-simplification  | Rewrite tests                     | pending   | --        | r-developer |

## Dependency Graph

```
E01-T001 --> E01-T002 --> E01-T004
E01-T001 --> E01-T003 --> E01-T004
E01-T004 --> E02-T001
E02-T001 --> E02-T002
E02-T001 + E02-T002 --> E02-T003
E02-T003 --> E02-T004
E02-T004 --> E03-T001
E03-T001 --> E03-T002
E03-T001 + E03-T002 --> E03-T003
E03-T003 --> E03-T004
E03-T003 + E03-T004 --> E03-T005
```

## Files Index

```
plans/simplification-refactor/
  00-master-plan.md
  README.md
  .implementation-state.json
  epic-01-per-plant-resilience/
    00-epic-overview.md
    ticket-001-plant-error-sentinel.md
    ticket-002-train-resilience.md
    ticket-003-predict-resilience.md
    ticket-004-resilience-integration-tests.md
  epic-02-environment-provenance-metrics/
    00-epic-overview.md
    ticket-001-provenance-as-environment.md
    ticket-002-metrics-as-environment.md
    ticket-003-remove-superassign-pipelines.md
    ticket-004-environment-tests.md
  epic-03-model-strategy-simplification/
    00-epic-overview.md
    ticket-001-rewrite-model-strategy.md
    ticket-002-rewrite-model-linear-regression.md
    ticket-003-update-artifact-train-predict.md
    ticket-004-update-namespace-cli.md
    ticket-005-rewrite-tests.md
```
