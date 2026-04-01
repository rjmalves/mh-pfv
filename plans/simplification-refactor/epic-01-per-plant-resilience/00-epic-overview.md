# Epic 01: Per-Plant Resilience

## Objective

Wrap plant processing (`ajustar_usina` in train, `processar_usina` in predict) in `tryCatch` so that a failure in one plant does not abort the entire pipeline. Failed plants are recorded with correct provenance status; successful plants get their artifacts written and checkpoints updated.

## Context

Currently, if any single plant throws an error in the `lapply` or `future_lapply` loop, the entire result vector is never assigned. The post-processing loop (artifact writing, provenance updates, checkpoint writes) never executes. All plants end up as "pending" in provenance regardless of what actually happened.

## Tickets

| ID       | Name                         | Description                                           |
| -------- | ---------------------------- | ----------------------------------------------------- |
| E01-T001 | Plant Error Sentinel         | Create `plant_error()` constructor and helpers        |
| E01-T002 | Train Pipeline Resilience    | Add `tryCatch` to serial and parallel train loops     |
| E01-T003 | Predict Pipeline Resilience  | Add `tryCatch` to serial and parallel predict loops   |
| E01-T004 | Resilience Integration Tests | Tests for partial failure scenarios in both pipelines |

## Success Criteria

- A pipeline with 4 plants where 1 fails produces:
  - 3 written artifacts (train) or 3 processed results (predict)
  - Provenance with 3 "completed" + 1 "failed"
  - Checkpoint written with correct per-plant status
  - Health report with `overall_health: "failed"` and per-plant error detail
- Resume after partial failure skips completed plants and retries failed ones
