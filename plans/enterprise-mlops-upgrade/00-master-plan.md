# Master Plan: Enterprise MLOps Upgrade for mhpfv

## Executive Summary

The mhpfv package (Melhor Historico de Insumos para Previsao de Solar Fotovoltaica) is a production R package operated by ONS for consolidating historical solar photovoltaic generation data. This plan upgrades the package from its current v0.1.1 state to enterprise-grade MLOps standards across six epics: quality foundation, extensibility refactoring, performance parallelization, MLOps provenance, infrastructure hardening, and observability. All changes maintain backward compatibility with the existing JSONC configuration format and I/O contracts.

## Goals and Non-Goals

### Goals

1. **Quality**: Achieve measurable test coverage with unit, integration, and end-to-end tests; add snapshot testing for regression detection
2. **Extensibility**: Introduce S3-class pluggable model framework; internalize main.r into the package boundary
3. **Performance**: Parallelize per-plant processing using future/parallel; cache expensive computations (Haversine distances)
4. **MLOps**: Add model versioning with metadata; run provenance tracking; pipeline resume on failure; data validation framework
5. **Infrastructure**: Optimize Docker image (multi-stage build, smaller base); enhance CI/CD with quality gates
6. **Observability**: Structured logging with run context; performance metrics collection; alerting hooks

### Non-Goals

- REST API / real-time serving (batch CLI only)
- Cloud-specific code in mhpfv (S3/cloud backends belong in pfvIO)
- Replacing data.table with another framework
- Changing the core regression algorithm (Gen_h = alpha_h x Irrad_h)
- Migrating away from R

## Architecture Overview

### Current State

```
main.r (678 lines, outside package)
    |
    v
mhpfv package (11 R files, ~1700 lines)
    |
    v
pfvIO (I/O layer, team-owned)
    |
    v
Parquet/CSV files on disk
```

- Sequential per-plant processing via `lapply`
- Plain RDS artifacts with no metadata
- No model abstraction (hardcoded linear regression)
- No run provenance or experiment tracking
- No pipeline resume capability

### Target State

```
mhpfv::cli_main() (internalized entry point)
    |
    v
mhpfv package (modular, ~2500 lines)
    |-- S3 model strategy (pluggable: linear_regression, future models)
    |-- Pipeline orchestrator (resume, provenance, validation)
    |-- Parallel per-plant processing (future/parallel)
    |-- Structured logging with run context
    |
    v
pfvIO (I/O layer with validation, versioned artifacts)
    |
    v
Parquet/CSV/RDS files (with metadata)
```

### Key Design Decisions

| Decision        | Choice                         | Rationale                                       |
| --------------- | ------------------------------ | ----------------------------------------------- |
| Model strategy  | S3-class dispatch              | Matches codebase conventions; zero dependencies |
| Parallelism     | future/parallel packages       | R-native, in-process, simple API                |
| pfvIO role      | I/O + validation layer         | mhpfv stays storage-agnostic                    |
| API mode        | Batch CLI only                 | No REST needed per requirements                 |
| Config compat   | Additive optional fields       | Existing configs keep working unchanged         |
| State tracking  | JSON state file                | Simple, human-readable, no DB dependency        |
| Artifact format | RDS with metadata list wrapper | Backward compatible, extensible                 |
| Entry point     | Internalize main.r             | Makes it testable, lint-able, package-managed   |

## Technical Approach

### Tech Stack

- **Language**: R >= 4.0
- **Data manipulation**: data.table (exclusive)
- **OOP**: S3 classes (exclusive)
- **Testing**: testthat v3
- **Documentation**: roxygen2 with markdown
- **Logging**: lgr
- **I/O**: pfvIO (team-owned), arrow
- **Parallelism**: future, future.apply (to be added)
- **CI/CD**: GitHub Actions (existing)
- **Container**: Docker (to be optimized)

### Component/Module Breakdown

1. **config-file.r** -- Configuration parsing (existing, minor extensions)
2. **consistencia-dados.r** -- Data consistency validation (existing, add data validation framework)
3. **train.r** -- Model training (refactor to use strategy pattern)
4. **predict.r** -- Prediction pipeline (refactor to use strategy, add resume)
5. **preenchimento-dados-faltantes.r** -- Missing data imputation (existing, minor changes)
6. **utils.r** -- Utilities (add caching, refactor NWP association)
7. **escrita.r** -- Output writing (add metadata)
8. **model-strategy.r** -- NEW: S3 model abstraction layer
9. **pipeline.r** -- NEW: Pipeline orchestration with resume and provenance
10. **validation.r** -- NEW: Data validation framework
11. **cli.r** -- NEW: Internalized CLI entry point (from main.r)
12. **logging.r** -- Enhanced structured logging
13. **parser.r** -- CLI argument parsing (existing)
14. **mh-pfv.r** -- Package metadata (update imports)
15. **zzz.r** -- Package hooks (update)

### Data Flow

```
CLI args --> parse_config() --> validate_inputs()
    |
    v
pipeline_run() {
    run_id = generate_run_id()
    state = load_or_create_state()

    for each plant (parallel):
        if (already_completed(plant, state)): skip  # resume

        data = get_dataset(plant)
        validate_data(data)

        if (mode == "train"):
            model = fit_model(strategy, data)  # S3 dispatch
            save_artifact(model, metadata)

        if (mode == "predict"):
            model = load_artifact(plant)
            result = predict_model(strategy, model, data)  # S3 dispatch

        update_state(plant, state)

    write_outputs()
    write_provenance(run_id, metrics)
}
```

### Testing Strategy

- **Unit tests**: Each function in isolation with synthetic data (existing pattern, expand coverage)
- **Integration tests**: Full train/predict pipeline with test dataset (NEW)
- **Snapshot tests**: Regression output comparison against golden files (NEW)
- **Property-based tests**: Numeric algorithm invariants (NEW, selective)

## Phases and Milestones

### Epic 1: Quality Foundation (Weeks 1-3)

- Measure and increase test coverage to >= 80%
- Add integration tests for train and predict pipelines
- Add snapshot tests for numerical outputs
- Internalize main.r into package (prerequisite for testability)

### Epic 2: Extensibility Refactor (Weeks 3-5)

- Implement S3 model strategy pattern
- Refactor train.r and predict.r to use strategy
- Add input data validation framework
- Ensure backward compatibility throughout

### Epic 3: Performance and Parallelization (Weeks 5-7)

- Add future/parallel infrastructure
- Parallelize per-plant processing in train and predict
- Cache Haversine distance computations
- Add benchmarking infrastructure

### Epic 4: MLOps and Provenance (Weeks 7-9)

- Model versioning with metadata in artifacts
- Run provenance (run ID, timestamps, metrics)
- Pipeline resume on failure
- Model comparison framework

### Epic 5: Infrastructure Hardening (Weeks 9-10)

- Docker multi-stage build optimization
- CI/CD quality gates enhancement
- Resource limits and configuration

### Epic 6: Observability and Monitoring (Weeks 10-11)

- Structured logging with run context
- Performance metrics collection
- Pipeline health reporting

## Risk Analysis

| Risk                                               | Probability | Impact   | Mitigation                                              |
| -------------------------------------------------- | ----------- | -------- | ------------------------------------------------------- |
| pfvIO changes break mhpfv                          | Medium      | High     | Pin pfvIO version; test against specific tag            |
| Parallel processing introduces race conditions     | Low         | High     | Use future (fork-safe); no shared mutable state         |
| Backward compatibility broken                      | Low         | Critical | Integration test with production config; snapshot tests |
| Test data too small for meaningful coverage        | Medium      | Medium   | Expand test dataset; use synthetic data generators      |
| S3 model abstraction adds complexity without value | Low         | Medium   | Keep interface minimal; concrete benefit is testability |

## Success Metrics

| Metric                     | Current                 | Target                                      |
| -------------------------- | ----------------------- | ------------------------------------------- |
| Test coverage (line)       | Unknown                 | >= 80%                                      |
| Integration test pass rate | 0 tests                 | 100%                                        |
| Per-plant parallelization  | Sequential              | N cores                                     |
| Docker image size          | ~2GB (rocker/tidyverse) | < 800MB                                     |
| Pipeline resume capability | None                    | Full resume from last checkpoint            |
| Model artifact metadata    | None                    | Version, timestamp, metrics, config hash    |
| CI/CD quality gates        | Lint + R-CMD-check      | + coverage threshold + benchmark regression |
