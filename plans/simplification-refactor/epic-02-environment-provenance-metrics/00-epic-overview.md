# Epic 02: Environment Provenance & Metrics

## Objective

Replace the copy-on-modify list representation of `provenance` and `metrics` with R environments that have reference semantics. This eliminates all `<<-` usage in the train/predict pipelines and removes N copies per N plants.

## Context

After Epic 01, the train and predict pipelines have `tryCatch` in place. The `<<-` assignments for `provenance` and `metrics` are still present. This epic replaces those lists with environments, making mutations in-place and removing `<<-`.

## Tickets

| ID       | Name                         | Description                                                                              |
| -------- | ---------------------------- | ---------------------------------------------------------------------------------------- |
| E02-T001 | Provenance as Environment    | Rewrite `create_provenance`, `update_plant_status`, `finalize_provenance`, serialization |
| E02-T002 | Metrics as Environment       | Rewrite `create_metrics`, `record_plant_*`, `finalize_metrics`, serialization            |
| E02-T003 | Remove <<- from Pipelines    | Update `train.r` and `predict.r` to drop all `<<-` for provenance/metrics                |
| E02-T004 | Environment Adaptation Tests | Update all tests that assert on provenance/metrics structure                             |

## Success Criteria

- Zero `<<-` for `provenance` or `metrics` in `train.r` and `predict.r`
- JSON output is identical to current format (no external consumer impact)
- All existing tests pass after adaptation
- `on.exit` handlers work correctly (reference to same environment)
