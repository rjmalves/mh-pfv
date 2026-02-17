# Epic 04: MLOps and Provenance

## Goal

Add model versioning with metadata to artifacts, pipeline run provenance tracking (run ID, timestamps, input hashes, output metrics), pipeline resume on failure, and a model comparison framework. Transform mhpfv from a batch script into a traceable, auditable ML pipeline.

## Scope

1. Enrich model artifacts with metadata (version, timestamp, config hash, training metrics)
2. Add run provenance tracking (run ID, start/end time, input file hashes, output checksums)
3. Implement pipeline resume on failure (per-plant checkpoint state)
4. Add model comparison utilities (compare coefficients across artifact versions)
5. Write provenance to a structured JSON file alongside outputs

## Out of Scope

- Experiment tracking with external tools (MLflow, Weights & Biases)
- Model registry / model serving
- Database-backed metadata storage

## Success Criteria

- Every model artifact includes metadata (type, version, timestamp, config hash, training metrics)
- Every pipeline run produces a provenance JSON file
- A failed pipeline can be resumed from the last successful plant
- Model comparison reports differences between artifact versions

## Tickets

| ID       | Title                                | Effort | Dependencies |
| -------- | ------------------------------------ | ------ | ------------ |
| E04-T001 | Enrich model artifacts with metadata | Medium | E02-T003     |
| E04-T002 | Add run provenance tracking          | Medium | E02-T004     |
| E04-T003 | Implement pipeline resume on failure | Large  | E04-T002     |
| E04-T004 | Add model comparison utilities       | Medium | E04-T001     |

## Estimated Duration

2-3 weeks with 2-3 developers.

## Dependencies on Other Epics

- **Epic 02**: Model strategy must be in place for metadata extraction
- **Epic 03** (optional): Parallelism does not block provenance but resume logic must be compatible with parallel execution
