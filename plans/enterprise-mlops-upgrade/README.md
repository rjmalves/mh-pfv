# Enterprise MLOps Upgrade Plan for mhpfv

## Overview

This plan upgrades the mhpfv R package (v0.1.1) from its current state to enterprise-grade MLOps standards. The package, operated by ONS (Brazilian national power grid operator), consolidates historical solar photovoltaic generation data through a train/predict pipeline using linear regression models.

The upgrade is organized into 6 epics covering quality, extensibility, performance, MLOps, infrastructure, and observability. Epics 1-4 are completed. Epic 5 tickets have been refined with learnings from Epics 1-4 and are ready for implementation. Epic 6 has outline tickets that will be refined after Epic 5.

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

| Epic | Name                            | Tickets | Status    | Detail Level |
| ---- | ------------------------------- | ------- | --------- | ------------ |
| 01   | Quality Foundation              | 8       | completed | Detailed     |
| 02   | Extensibility Refactor          | 6       | completed | Detailed     |
| 03   | Performance and Parallelization | 5       | completed | Refined      |
| 04   | MLOps and Provenance            | 4       | completed | Refined      |
| 05   | Infrastructure Hardening        | 3       | executing | Refined      |
| 06   | Observability and Monitoring    | 3       | pending   | Outline      |

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

Epic 03: Performance (completed)
    E03-T001 --> E03-T002 --> E03-T003 --> E03-T005
    E03-T004 (cache) is independent

Epic 04: MLOps (completed)
    E04-T001 (artifact metadata) -----> E04-T004 (model comparison)
    E04-T001 (artifact metadata) -----> E04-T002 (run provenance)
    E04-T002 (run provenance) --------> E04-T003 (pipeline resume)

Epic 05: Infrastructure (refined, ready for execution)
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

### Phase C (Weeks 5-7): Performance -- Epic 03

Sequential parallelization chain, with cache in parallel:

- **Dev 1**: E03-T001 -> E03-T002 -> E03-T003 -> E03-T005 (parallel infrastructure chain)
- **Dev 2**: E03-T004 (cache haversine, independent)

### Phase D (Weeks 7-9): MLOps and Provenance -- Epic 04

Two parallel chains:

- **Dev 1**: E04-T001 (artifact metadata) -> E04-T004 (model comparison)
- **Dev 2**: E04-T001 (must wait) -> E04-T002 (run provenance) -> E04-T003 (pipeline resume)

### Phase E (Weeks 9-11): Infrastructure and Observability -- Epics 5-6

All three Epic 05 tickets are independent and can be executed in parallel:

- **Dev 1**: E05-T001 (Docker optimization)
- **Dev 2**: E05-T002 (CI quality gates)
- **Dev 3**: E05-T003 (resource configuration)

Then refine and execute Epic 06 outline tickets.

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
| E02-T001 | Design model strategy interface    | epic-02 | completed | Detailed     |
| E02-T002 | Wrap linear regression as strategy | epic-02 | completed | Detailed     |
| E02-T003 | Refactor train.r to use strategy   | epic-02 | completed | Detailed     |
| E02-T004 | Refactor predict.r to use strategy | epic-02 | completed | Detailed     |
| E02-T005 | Add input validation framework     | epic-02 | completed | Detailed     |
| E02-T006 | Add strategy and validation tests  | epic-02 | completed | Detailed     |
| E03-T001 | Add parallel infrastructure        | epic-03 | completed | Refined      |
| E03-T002 | Parallelize train_main             | epic-03 | completed | Refined      |
| E03-T003 | Parallelize predict_main           | epic-03 | completed | Refined      |
| E03-T004 | Cache Haversine distances          | epic-03 | completed | Refined      |
| E03-T005 | Add benchmarking infrastructure    | epic-03 | completed | Refined      |
| E04-T001 | Enrich artifacts with metadata     | epic-04 | completed | Refined      |
| E04-T002 | Add run provenance tracking        | epic-04 | completed | Refined      |
| E04-T003 | Implement pipeline resume          | epic-04 | completed | Refined      |
| E04-T004 | Add model comparison utilities     | epic-04 | completed | Refined      |
| E05-T001 | Optimize Docker image              | epic-05 | completed | Refined      |
| E05-T002 | Enhance CI/CD quality gates        | epic-05 | completed | Refined      |
| E05-T003 | Add resource configuration         | epic-05 | completed | Refined      |
| E06-T001 | Enhance structured logging         | epic-06 | pending   | Outline      |
| E06-T002 | Add pipeline metrics collection    | epic-06 | pending   | Outline      |
| E06-T003 | Create pipeline health report      | epic-06 | pending   | Outline      |
