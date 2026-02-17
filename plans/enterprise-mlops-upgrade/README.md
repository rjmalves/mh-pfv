# Enterprise MLOps Upgrade Plan for mhpfv

## Overview

This plan upgrades the mhpfv R package (v0.1.1) from its current state to enterprise-grade MLOps standards. The package, operated by ONS (Brazilian national power grid operator), consolidates historical solar photovoltaic generation data through a train/predict pipeline using linear regression models.

The upgrade is organized into 6 epics covering quality, extensibility, performance, MLOps, infrastructure, and observability. Epics 1-2 have fully detailed tickets ready for implementation. Epics 3-6 have outline tickets that will be refined with learnings from earlier epics.

## Decision Log

| #   | Decision        | Choice                                                      | Rationale                                               |
| --- | --------------- | ----------------------------------------------------------- | ------------------------------------------------------- |
| 1   | Priority        | Balanced across quality, performance, MLOps, infrastructure | Interleaved across epics to deliver value incrementally |
| 2   | pfvIO Package   | Owned by team, modifiable                                   | pfvIO will get new backends (S3, etc.) as needed        |
| 3   | AWS Integration | Via pfvIO backends                                          | mhpfv stays storage-agnostic; pfvIO handles S3          |
| 4   | Model Strategy  | Pluggable S3-class framework                                | Keep current regression, design for future models       |
| 5   | API Mode        | Batch CLI only                                              | No REST API needed                                      |
| 6   | Parallelism     | R-native (future/parallel)                                  | In-process parallelism, simple API                      |
| 7   | Team            | Small team (2-3 devs), aggressive timeline                  | Tickets sized for ~30 min agent time                    |
| 8   | Compatibility   | Maintain backward compatibility                             | Existing config, inputs, and outputs unchanged          |

## Epic Overview

| Epic | Name                            | Tickets | Status  | Detail Level |
| ---- | ------------------------------- | ------- | ------- | ------------ |
| 01   | Quality Foundation              | 8       | pending | Detailed     |
| 02   | Extensibility Refactor          | 6       | pending | Detailed     |
| 03   | Performance and Parallelization | 5       | pending | Outline      |
| 04   | MLOps and Provenance            | 4       | pending | Outline      |
| 05   | Infrastructure Hardening        | 3       | pending | Outline      |
| 06   | Observability and Monitoring    | 3       | pending | Outline      |

## Dependency Graph

```
Epic 01: Quality Foundation
    E01-T001 (coverage baseline) -----> E01-T007, E01-T008
    E01-T002 (test helpers) ----------> E01-T004, E01-T005, E01-T006, E01-T007
    E01-T003 (internalize main.r) ----> E01-T004, E01-T005
    E01-T004 (integration train) -----> E01-T005, E01-T006
    E01-T005 (integration predict) ---> E01-T006
    E01-T006 (snapshot tests) --------> E02-T001
    E01-T007 (expand coverage) -------> E01-T008
    E01-T008 (CI threshold) ----------> (none)

Epic 02: Extensibility Refactor
    E02-T001 (strategy interface) ----> E02-T002
    E02-T002 (linear regression) -----> E02-T003
    E02-T003 (refactor train) --------> E02-T004
    E02-T004 (refactor predict) ------> E02-T006, E03-*, E04-*
    E02-T005 (validation) ------------> E02-T006
    E02-T006 (strategy tests) --------> (none)

Epic 03: Performance (outline)
    E03-T001 --> E03-T002 --> E03-T003 --> E03-T005
    E03-T004 (cache) is independent

Epic 04: MLOps (outline)
    E04-T001 --> E04-T004
    E04-T002 --> E04-T003

Epic 05: Infrastructure (outline)
    E05-T001, E05-T002, E05-T003 are largely independent

Epic 06: Observability (outline)
    E06-T001, E06-T002 --> E06-T003
```

## Execution Order Recommendation

### Phase A (Weeks 1-3): Quality Foundation -- Epic 01

Start all 3 independent tickets in parallel:

- **Dev 1**: E01-T001 (coverage baseline), then E01-T007 (expand coverage), then E01-T008 (CI threshold)
- **Dev 2**: E01-T002 (test helpers), then E01-T004 (integration train), then E01-T005 (integration predict)
- **Dev 3**: E01-T003 (internalize main.r), then help with E01-T006 (snapshot tests)

### Phase B (Weeks 3-5): Extensibility -- Epic 02

Sequential strategy chain, with validation in parallel:

- **Dev 1+2**: E02-T001 -> E02-T002 -> E02-T003 -> E02-T004 (strategy chain)
- **Dev 3**: E02-T005 (validation framework, independent)
- **All**: E02-T006 (comprehensive tests, after E02-T004 and E02-T005)

### Phase C (Weeks 5-11): Epics 3-6

Refine outline tickets using learnings from Epics 1-2, then execute.

## Ticket Status Tracking

| Ticket   | Title                              | Epic    | Status    | Detail Level |
| -------- | ---------------------------------- | ------- | --------- | ------------ |
| E01-T001 | Measure baseline test coverage     | epic-01 | completed | Detailed     |
| E01-T002 | Create test helper module          | epic-01 | completed | Detailed     |
| E01-T003 | Internalize main.r into package    | epic-01 | completed | Detailed     |
| E01-T004 | Add integration test for train     | epic-01 | completed | Detailed     |
| E01-T005 | Add integration test for predict   | epic-01 | completed | Detailed     |
| E01-T006 | Add snapshot tests                 | epic-01 | completed | Detailed     |
| E01-T007 | Expand unit test coverage          | epic-01 | completed | Detailed     |
| E01-T008 | Add coverage threshold to CI       | epic-01 | completed | Detailed     |
| E02-T001 | Design model strategy interface    | epic-02 | pending   | Detailed     |
| E02-T002 | Wrap linear regression as strategy | epic-02 | pending   | Detailed     |
| E02-T003 | Refactor train.r to use strategy   | epic-02 | pending   | Detailed     |
| E02-T004 | Refactor predict.r to use strategy | epic-02 | pending   | Detailed     |
| E02-T005 | Add input validation framework     | epic-02 | pending   | Detailed     |
| E02-T006 | Add strategy and validation tests  | epic-02 | pending   | Detailed     |
| E03-T001 | Add parallel infrastructure        | epic-03 | pending   | Outline      |
| E03-T002 | Parallelize train_main             | epic-03 | pending   | Outline      |
| E03-T003 | Parallelize predict_main           | epic-03 | pending   | Outline      |
| E03-T004 | Cache Haversine distances          | epic-03 | pending   | Outline      |
| E03-T005 | Add benchmarking infrastructure    | epic-03 | pending   | Outline      |
| E04-T001 | Enrich artifacts with metadata     | epic-04 | pending   | Outline      |
| E04-T002 | Add run provenance tracking        | epic-04 | pending   | Outline      |
| E04-T003 | Implement pipeline resume          | epic-04 | pending   | Outline      |
| E04-T004 | Add model comparison utilities     | epic-04 | pending   | Outline      |
| E05-T001 | Optimize Docker image              | epic-05 | pending   | Outline      |
| E05-T002 | Enhance CI/CD quality gates        | epic-05 | pending   | Outline      |
| E05-T003 | Add resource configuration         | epic-05 | pending   | Outline      |
| E06-T001 | Enhance structured logging         | epic-06 | pending   | Outline      |
| E06-T002 | Add pipeline metrics collection    | epic-06 | pending   | Outline      |
| E06-T003 | Create pipeline health report      | epic-06 | pending   | Outline      |
