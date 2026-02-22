# E04-T004 Add Model Comparison Utilities

## Context

### Background

Model artifacts now contain metadata (type, n_slots, n_valid_slots, mean_coefficient, timestamp, package_version, config_hash) thanks to E04-T001. However, there is no way for operators to compare two model artifacts -- for example, comparing this week's trained model against last week's, or comparing a model trained with one configuration against another. Understanding how model parameters change over time is essential for detecting drift, validating retraining, and debugging production issues.

This ticket creates comparison utility functions that take two (or more) model artifacts and produce structured reports showing differences in metadata and coefficients.

### Relation to Epic

This is the fourth and final ticket in Epic 04 (MLOps and Provenance). It consumes the enriched artifact structure from E04-T001 and provides the analytical capability that closes the MLOps loop: train (artifacts with metadata) -> track (provenance) -> resume (checkpoints) -> compare (this ticket).

### Current State

**Artifact structure** (after E04-T001):

```r
list(
    id_usina = "BAUFI1",
    parametros = data.frame(
        a = c(0.01, 0.02, ...),  # angular coefficients per time slot
        b = c(0, 0, ...),        # intercept, always 0
        row.names = c("05:00", "05:30", ..., "18:00", "18:30")
    ),
    metadata = list(
        type = "linear_regression",
        n_slots = 28L,
        n_valid_slots = 26L,
        mean_coefficient = 0.03,
        timestamp = <POSIXct>,
        package_version = "0.1.1",
        config_hash = "sha256:..."
    )
)
```

**`model_metadata()` S3 generic** (`/home/rogerio/git/mh-pfv/R/model-strategy.r`, lines 104-112): already dispatches on strategy type.

**`model_metadata.linear_regression`** (`/home/rogerio/git/mh-pfv/R/model-linear-regression.r`, lines 82-97): extracts type, n_slots, n_valid_slots, mean_coefficient, timestamp.

**Test helper** (`/home/rogerio/git/mh-pfv/tests/testthat/helper-generators.r`): `gen_model_artifact()` returns an enriched artifact with metadata (after E04-T001). `gen_model_artifact_legacy()` returns old format.

## Specification

### Requirements

1. **Create `R/model-comparison.r`**: New file containing all model comparison functions.

2. **`compare_artifacts(artifact_a, artifact_b)`**: Compare two model artifacts. Returns a structured comparison report as a plain list with:
   - `id_usina_a`, `id_usina_b`: plant IDs from each artifact
   - `metadata_diff`: list of metadata fields that differ (each entry has `field`, `value_a`, `value_b`)
   - `coefficient_diff`: data.table comparing coefficients by time slot:
     - `slot`: character, time slot name (e.g., "05:00")
     - `a_artifact_a`: numeric, coefficient from artifact A
     - `a_artifact_b`: numeric, coefficient from artifact B
     - `diff`: numeric, `a_artifact_b - a_artifact_a`
     - `pct_change`: numeric, percentage change (NA where base is 0 or NA)
   - `summary`: list with aggregate metrics:
     - `mean_diff`: mean absolute difference across all valid slots
     - `max_diff`: maximum absolute difference
     - `n_changed_slots`: number of slots where coefficient changed
     - `n_new_na`: number of slots that became NA (valid in A, NA in B)
     - `n_recovered`: number of slots that recovered (NA in A, valid in B)

3. **`compare_artifact_files(path_a, path_b)`**: Convenience wrapper that reads two RDS artifact files and calls `compare_artifacts()`. Validates both files exist.

4. **`format_comparison(comparison)`**: Produces a human-readable text report from a comparison result. Returns a character vector of lines (one per logical row). The report includes:
   - Header with plant IDs and timestamps
   - Metadata differences table
   - Coefficient changes summary
   - Top 5 slots with largest absolute difference
   - Slots that gained or lost validity (NA changes)

5. **`compare_multiple_artifacts(artifacts, labels)`**: Compare a list of 2+ artifacts, producing a pairwise comparison matrix. Returns a list of `compare_artifacts()` results for each pair. Useful for comparing the same plant across multiple training runs.

6. **Backward compatibility**: All comparison functions must handle artifacts in both old format (without metadata) and new format. For old-format artifacts, metadata comparison is skipped (with a message in the report noting "metadados nao disponiveis").

7. **Cross-type guard**: If two artifacts have different model types (e.g., `linear_regression` vs a future type), `compare_artifacts()` should raise a warning that coefficient comparison may not be meaningful, but still produce the comparison.

### Inputs/Props

- `compare_artifacts(artifact_a, artifact_b)`:
  - `artifact_a`, `artifact_b`: model artifact lists (with or without metadata)
- `compare_artifact_files(path_a, path_b)`:
  - `path_a`, `path_b`: file paths to RDS artifact files
- `format_comparison(comparison)`:
  - `comparison`: the list returned by `compare_artifacts()`
- `compare_multiple_artifacts(artifacts, labels)`:
  - `artifacts`: list of model artifact lists
  - `labels`: character vector of labels for each artifact (e.g., "2026-02-10", "2026-02-17")

### Outputs/Behavior

- `compare_artifacts()` returns a structured list (not printed).
- `compare_artifact_files()` returns the same structured list.
- `format_comparison()` returns a character vector of formatted text lines. Example:

  ```
  Comparacao de Artefatos de Modelo
  ==================================
  Usina A: BAUFI1 (2026-02-10 14:30:52)
  Usina B: BAUFI1 (2026-02-17 09:15:33)

  Diferencas de Metadados:
    config_hash: sha256:abc... -> sha256:def...
    n_valid_slots: 26 -> 27
    mean_coefficient: 0.030 -> 0.032

  Resumo de Coeficientes:
    Slots com mudanca: 15 de 28
    Diferenca media absoluta: 0.0023
    Diferenca maxima absoluta: 0.0089 (slot 12:00)
    Slots com NA novo: 0
    Slots recuperados: 1

  Maiores Diferencas:
    12:00  0.0250 -> 0.0339  (+35.6%)
    13:00  0.0310 -> 0.0370  (+19.4%)
    ...
  ```

- `compare_multiple_artifacts()` returns a named list of comparison results.

### Error Handling

- `compare_artifacts()` validates both inputs are lists with at least `parametros` field. Raises an error if not.
- `compare_artifact_files()` validates both paths exist, raises an error with the missing path if not.
- If row names of `parametros` do not match between artifacts (different time slot grids), the comparison aligns by slot name using a full outer join, with NA for missing slots.
- All error messages in Portuguese.

## Acceptance Criteria

- [ ] Given two artifacts with the same coefficients and metadata, when `compare_artifacts()` is called, then `coefficient_diff$diff` is all zeros and `metadata_diff` is empty
- [ ] Given two artifacts with different coefficients, when `compare_artifacts()` is called, then `coefficient_diff` correctly shows the differences and `summary$n_changed_slots` is positive
- [ ] Given two artifacts where some slots became NA, when `compare_artifacts()` is called, then `summary$n_new_na` reflects the count correctly
- [ ] Given two artifacts with different metadata, when `compare_artifacts()` is called, then `metadata_diff` lists the differing fields with both values
- [ ] Given an old-format artifact (without metadata) and a new-format artifact, when `compare_artifacts()` is called, then coefficient comparison works and metadata comparison reports "metadados nao disponiveis" for the old artifact
- [ ] Given two RDS artifact file paths, when `compare_artifact_files(path_a, path_b)` is called, then the result is identical to manually loading and calling `compare_artifacts()`
- [ ] Given a non-existent file path, when `compare_artifact_files()` is called, then it raises an error mentioning the missing file
- [ ] Given a comparison result, when `format_comparison()` is called, then it returns a character vector with the human-readable report
- [ ] Given a list of 3 artifacts, when `compare_multiple_artifacts()` is called, then it returns 3 pairwise comparison results (A-B, A-C, B-C)
- [ ] Given two artifacts with different model types, when `compare_artifacts()` is called, then it produces a comparison with a warning about cross-type comparison

## Implementation Guide

### Suggested Approach

**Step 1: Create `R/model-comparison.r`**

```r
#' Compara Dois Artefatos de Modelo
#'
#' Produz um relatorio estruturado de diferencas entre dois artefatos,
#' incluindo metadados e coeficientes.
#'
#' @param artifact_a lista, primeiro artefato de modelo
#' @param artifact_b lista, segundo artefato de modelo
#'
#' @return lista com campos: id_usina_a, id_usina_b, metadata_diff,
#'   coefficient_diff, summary
#'
#' @export
compare_artifacts <- function(artifact_a, artifact_b) {
    validate_comparison_input(artifact_a, "A")
    validate_comparison_input(artifact_b, "B")

    # Cross-type warning
    if (has_metadata(artifact_a) && has_metadata(artifact_b)) {
        type_a <- artifact_a$metadata$type
        type_b <- artifact_b$metadata$type
        if (!identical(type_a, type_b)) {
            warning(sprintf(
                paste0("Comparacao entre tipos diferentes de modelo ",
                    "('%s' vs '%s'): diferencas de coeficientes podem ",
                    "nao ser significativas"),
                type_a, type_b
            ), call. = FALSE)
        }
    }

    list(
        id_usina_a = artifact_a$id_usina,
        id_usina_b = artifact_b$id_usina,
        metadata_diff = compare_metadata(artifact_a, artifact_b),
        coefficient_diff = compare_coefficients(
            artifact_a$parametros, artifact_b$parametros
        ),
        summary = summarize_coefficient_diff(
            compare_coefficients(artifact_a$parametros, artifact_b$parametros)
        )
    )
}

# --- Internal helpers ---

validate_comparison_input <- function(artifact, label) {
    if (!is.list(artifact)) {
        stop(sprintf("Artefato %s deve ser uma lista", label), call. = FALSE)
    }
    if (!"parametros" %in% names(artifact)) {
        stop(sprintf(
            "Artefato %s deve conter campo 'parametros'", label
        ), call. = FALSE)
    }
    if (!is.data.frame(artifact$parametros)) {
        stop(sprintf(
            "Artefato %s: 'parametros' deve ser um data.frame", label
        ), call. = FALSE)
    }
    invisible(TRUE)
}

has_metadata <- function(artifact) {
    "metadata" %in% names(artifact) && is.list(artifact$metadata)
}

compare_metadata <- function(artifact_a, artifact_b) {
    has_a <- has_metadata(artifact_a)
    has_b <- has_metadata(artifact_b)

    if (!has_a && !has_b) {
        return(list(note = "Metadados nao disponiveis em ambos os artefatos"))
    }
    if (!has_a) {
        return(list(note = "Metadados nao disponiveis no artefato A"))
    }
    if (!has_b) {
        return(list(note = "Metadados nao disponiveis no artefato B"))
    }

    meta_a <- artifact_a$metadata
    meta_b <- artifact_b$metadata

    # Compare all common fields except timestamp (always differs)
    fields <- setdiff(
        union(names(meta_a), names(meta_b)),
        "timestamp"
    )

    diffs <- list()
    for (field in fields) {
        val_a <- meta_a[[field]]
        val_b <- meta_b[[field]]
        if (!identical(val_a, val_b)) {
            diffs[[length(diffs) + 1L]] <- list(
                field = field,
                value_a = val_a,
                value_b = val_b
            )
        }
    }

    # Include timestamps for reference (not compared)
    attr(diffs, "timestamp_a") <- meta_a$timestamp
    attr(diffs, "timestamp_b") <- meta_b$timestamp

    diffs
}

compare_coefficients <- function(params_a, params_b) {
    slots_a <- rownames(params_a)
    slots_b <- rownames(params_b)
    all_slots <- union(slots_a, slots_b)

    a_vals <- stats::setNames(
        rep(NA_real_, length(all_slots)),
        all_slots
    )
    b_vals <- a_vals

    a_vals[slots_a] <- params_a$a
    b_vals[slots_b] <- params_b$a

    diff_vals <- b_vals - a_vals
    pct_vals <- ifelse(
        is.na(a_vals) | a_vals == 0,
        NA_real_,
        (diff_vals / abs(a_vals)) * 100
    )

    data.table::data.table(
        slot = all_slots,
        a_artifact_a = a_vals,
        a_artifact_b = b_vals,
        diff = diff_vals,
        pct_change = pct_vals
    )
}

summarize_coefficient_diff <- function(coeff_dt) {
    valid_both <- !is.na(coeff_dt$a_artifact_a) & !is.na(coeff_dt$a_artifact_b)
    abs_diff <- abs(coeff_dt$diff)

    list(
        mean_diff = if (any(valid_both)) mean(abs_diff[valid_both]) else NA_real_,
        max_diff = if (any(valid_both)) max(abs_diff[valid_both]) else NA_real_,
        n_changed_slots = sum(valid_both & coeff_dt$diff != 0, na.rm = TRUE),
        n_new_na = sum(
            !is.na(coeff_dt$a_artifact_a) & is.na(coeff_dt$a_artifact_b)
        ),
        n_recovered = sum(
            is.na(coeff_dt$a_artifact_a) & !is.na(coeff_dt$a_artifact_b)
        )
    )
}
```

**Step 2: Add `compare_artifact_files()`**

```r
#' Compara Dois Artefatos de Modelo a Partir de Arquivos
#'
#' @param path_a character, caminho para o primeiro arquivo RDS
#' @param path_b character, caminho para o segundo arquivo RDS
#'
#' @return lista de comparacao (mesmo formato de [compare_artifacts()])
#'
#' @export
compare_artifact_files <- function(path_a, path_b) {
    if (!file.exists(path_a)) {
        stop(sprintf("Arquivo nao encontrado: '%s'", path_a), call. = FALSE)
    }
    if (!file.exists(path_b)) {
        stop(sprintf("Arquivo nao encontrado: '%s'", path_b), call. = FALSE)
    }

    artifact_a <- readRDS(path_a)
    artifact_b <- readRDS(path_b)

    compare_artifacts(artifact_a, artifact_b)
}
```

**Step 3: Add `format_comparison()`**

```r
#' Formata Relatorio de Comparacao de Artefatos
#'
#' @param comparison lista retornada por [compare_artifacts()]
#'
#' @return character vector com linhas do relatorio formatado
#'
#' @export
format_comparison <- function(comparison) {
    lines <- character(0L)

    lines <- c(lines, "Comparacao de Artefatos de Modelo")
    lines <- c(lines, "==================================")

    # Header
    ts_a <- attr(comparison$metadata_diff, "timestamp_a")
    ts_b <- attr(comparison$metadata_diff, "timestamp_b")
    ts_a_str <- if (!is.null(ts_a)) format(ts_a, " (%Y-%m-%d %H:%M:%S)") else ""
    ts_b_str <- if (!is.null(ts_b)) format(ts_b, " (%Y-%m-%d %H:%M:%S)") else ""

    lines <- c(lines, sprintf("Usina A: %s%s", comparison$id_usina_a, ts_a_str))
    lines <- c(lines, sprintf("Usina B: %s%s", comparison$id_usina_b, ts_b_str))
    lines <- c(lines, "")

    # Metadata
    lines <- c(lines, "Diferencas de Metadados:")
    md <- comparison$metadata_diff
    if (!is.null(md$note)) {
        lines <- c(lines, sprintf("  %s", md$note))
    } else if (length(md) == 0L) {
        lines <- c(lines, "  Nenhuma diferenca")
    } else {
        for (d in md) {
            lines <- c(lines, sprintf("  %s: %s -> %s",
                d$field,
                as.character(d$value_a),
                as.character(d$value_b)
            ))
        }
    }
    lines <- c(lines, "")

    # Coefficient summary
    s <- comparison$summary
    lines <- c(lines, "Resumo de Coeficientes:")
    coeff_dt <- comparison$coefficient_diff
    n_total <- nrow(coeff_dt)
    lines <- c(lines, sprintf("  Slots com mudanca: %d de %d",
        s$n_changed_slots, n_total))
    lines <- c(lines, sprintf("  Diferenca media absoluta: %.4f",
        if (is.na(s$mean_diff)) 0 else s$mean_diff))

    if (!is.na(s$max_diff) && s$max_diff > 0) {
        max_idx <- which.max(abs(coeff_dt$diff))
        max_slot <- coeff_dt$slot[max_idx]
        lines <- c(lines, sprintf("  Diferenca maxima absoluta: %.4f (slot %s)",
            s$max_diff, max_slot))
    }
    lines <- c(lines, sprintf("  Slots com NA novo: %d", s$n_new_na))
    lines <- c(lines, sprintf("  Slots recuperados: %d", s$n_recovered))
    lines <- c(lines, "")

    # Top differences
    valid_rows <- coeff_dt[!is.na(diff) & diff != 0]
    if (nrow(valid_rows) > 0L) {
        top_n <- min(5L, nrow(valid_rows))
        top <- valid_rows[order(-abs(diff))][seq_len(top_n)]
        lines <- c(lines, "Maiores Diferencas:")
        for (i in seq_len(nrow(top))) {
            r <- top[i]
            pct_str <- if (!is.na(r$pct_change)) {
                sprintf(" (%+.1f%%)", r$pct_change)
            } else {
                ""
            }
            lines <- c(lines, sprintf("  %s  %.4f -> %.4f%s",
                r$slot, r$a_artifact_a, r$a_artifact_b, pct_str))
        }
    }

    lines
}
```

**Step 4: Add `compare_multiple_artifacts()`**

```r
#' Compara Multiplos Artefatos de Modelo (Pairwise)
#'
#' @param artifacts lista de artefatos de modelo
#' @param labels character vector de rotulos para cada artefato
#'
#' @return lista nomeada de comparacoes pairwise
#'
#' @export
compare_multiple_artifacts <- function(artifacts, labels = NULL) {
    n <- length(artifacts)
    stopifnot(n >= 2L)

    if (is.null(labels)) {
        labels <- paste0("artifact_", seq_len(n))
    }
    stopifnot(length(labels) == n)

    comparisons <- list()
    for (i in seq_len(n - 1L)) {
        for (j in (i + 1L):n) {
            key <- paste0(labels[i], "_vs_", labels[j])
            comparisons[[key]] <- compare_artifacts(
                artifacts[[i]], artifacts[[j]]
            )
        }
    }

    comparisons
}
```

**Step 5: Update NAMESPACE**

Run `devtools::document()` to export `compare_artifacts`, `compare_artifact_files`, `format_comparison`, `compare_multiple_artifacts`.

### Key Files to Modify

| File                                                              | Change                                         |
| ----------------------------------------------------------------- | ---------------------------------------------- |
| `/home/rogerio/git/mh-pfv/R/model-comparison.r`                   | **NEW FILE** -- all comparison functions       |
| `/home/rogerio/git/mh-pfv/tests/testthat/test-model-comparison.r` | **NEW FILE** -- tests for comparison functions |
| `/home/rogerio/git/mh-pfv/NAMESPACE`                              | Regenerated by `devtools::document()`          |

### Patterns to Follow

- **data.table for structured output**: The `coefficient_diff` output is a `data.table`, matching the project's exclusive use of data.table for tabular data.
- **Plain list for complex return values**: Follow the pattern of `model_metadata()` returning a plain list.
- **S3 generics possible future**: While comparison is currently only for linear_regression, the function structure allows easy conversion to S3 dispatch if multiple model types need specialized comparison logic.
- **Portuguese messages**: All user-facing text in Portuguese.
- **Test helper usage**: Use `gen_model_artifact()` and `gen_model_artifact_legacy()` from helper-generators.r.

### Pitfalls to Avoid

- **Row name alignment**: The two artifacts may have different time slot sets (e.g., if one model failed to fit certain hours). Use `union()` of row names, not `intersect()`, and fill missing slots with NA.
- **Percentage change division by zero**: When `a_artifact_a` is 0 or NA, `pct_change` must be NA, not Inf.
- **`data.table` print behavior**: `data.table` prints differently than `data.frame` by default. Tests should use `expect_equal` on values, not on printed output.
- **Attribute preservation on comparison result**: The `metadata_diff` list uses `attr()` for timestamps. These survive serialization with `saveRDS()` but would be lost with JSON. Since comparison results are used in-session, this is acceptable.
- **Do NOT add plotting**: The outline mentioned possible visual comparison. Do not add ggplot2 or any visualization -- text reports only. Plotting is a separate concern.
- **No new dependencies**: This ticket does not require any new packages beyond what is already in DESCRIPTION (data.table, stats).

## Testing Requirements

### Unit Tests

Create `/home/rogerio/git/mh-pfv/tests/testthat/test-model-comparison.r`:

1. **Identical artifacts produce zero diff**: Compare `gen_model_artifact()` with itself, verify all diffs are 0 and metadata_diff is empty.
2. **Different coefficients detected**: Create two artifacts with different `a` values, verify `coefficient_diff$diff` is non-zero and `summary$n_changed_slots` is correct.
3. **NA detection**: Create artifact A with all valid coefficients, artifact B with some NA, verify `summary$n_new_na` counts correctly.
4. **Recovery detection**: Create artifact A with some NA, artifact B with all valid, verify `summary$n_recovered`.
5. **Metadata diff detected**: Create two artifacts with different `config_hash`, verify `metadata_diff` lists the field.
6. **Old-format artifact handling**: Compare `gen_model_artifact_legacy()` with `gen_model_artifact()`, verify coefficient comparison works and metadata notes say "nao disponiveis".
7. **Cross-type warning**: Create two artifacts with different `type` in metadata, verify a warning is raised.
8. **`compare_artifact_files` roundtrip**: Save two artifacts to `withr::local_tempdir()`, compare via file paths, verify result matches direct comparison.
9. **`compare_artifact_files` missing file error**: Pass non-existent path, verify error message includes the path.
10. **`format_comparison` produces non-empty output**: Format a comparison result, verify it is a character vector with content.
11. **`format_comparison` includes key sections**: Verify output contains "Comparacao de Artefatos", "Diferencas de Metadados", "Resumo de Coeficientes".
12. **`compare_multiple_artifacts` produces all pairs**: Compare 3 artifacts, verify 3 pairwise results returned.
13. **`compare_multiple_artifacts` rejects fewer than 2**: Pass 1 artifact, verify error.
14. **Different time slot grids**: Create artifacts with different `rownames` on `parametros`, verify comparison aligns by slot name with NA fill.
15. **Validate input rejects non-list**: Pass a character string, verify error.

### Integration Tests

No integration tests needed -- this ticket only adds pure functions that operate on in-memory data structures. All testing is at the unit level.

## Dependencies

- **Blocked By**: E04-T001 (enriched artifact structure with metadata)
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
