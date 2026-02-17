# E04-T002 Add Run Provenance Tracking

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Add a provenance tracking system that records metadata for every pipeline run: a unique run ID, start and end timestamps, input file checksums, config hash, number of plants processed, per-plant status, and output file checksums. Provenance is written to a JSON file alongside the outputs, enabling full auditability of every pipeline execution.

## Anticipated Scope

- **Files likely to be modified**: New file `R/provenance.r` for provenance tracking functions, `/home/rogerio/git/mh-pfv/R/cli.r` or `R/predict.r` / `R/train.r` (wrap pipeline execution with provenance tracking)
- **Key decisions needed**: Run ID format (UUID vs timestamp-based); which input files to checksum (all Parquet/CSV in the data directory, or just the ones actually read?); where to store the provenance JSON (output directory, separate provenance directory, or both); whether to use jsonlite for JSON serialization
- **Open questions**: Should provenance capture the R session info (R version, package versions)? How should parallel execution metadata be recorded (number of workers, per-worker timing)?

## Dependencies

- **Blocked By**: E02-T004
- **Blocks**: E04-T003

## Effort Estimate

**Points**: 3
**Confidence**: Low (will be re-estimated during refinement)
