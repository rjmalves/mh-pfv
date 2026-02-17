# E04-T001 Enrich Model Artifacts with Metadata

> **[OUTLINE]** This ticket requires refinement before execution.
> It will be refined with learnings from earlier epics.

## Objective

Wrap model artifacts (currently plain RDS files containing `list(id_usina, parametros)`) with a metadata layer that records model type, package version, training timestamp, config hash, and training metrics. The artifact format must remain backward-compatible: existing code that reads `model[[1]]` (id_usina) and `model[[2]]` (parametros) must continue to work.

## Anticipated Scope

- **Files likely to be modified**: `/home/rogerio/git/mh-pfv/R/train.r` (artifact construction), `/home/rogerio/git/mh-pfv/R/escrita.r` or a new `R/artifact.r` (metadata wrapper), possibly pfvIO's `write_model_artifact`
- **Key decisions needed**: Whether metadata is stored as additional list elements (model[[3]] = metadata) or as attributes on the list; how to compute config hash (digest package vs base R); what training metrics to include (n_plants, n_valid_slots, mean_coefficient from model_metadata)
- **Open questions**: Does pfvIO's `get_model_artifact()` strip attributes when reading RDS? Should old artifacts without metadata be handled gracefully (backward read compatibility)?

## Dependencies

- **Blocked By**: E02-T003
- **Blocks**: E04-T004

## Effort Estimate

**Points**: 2
**Confidence**: Low (will be re-estimated during refinement)
