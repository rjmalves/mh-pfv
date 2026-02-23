#' Compara Dois Artefatos de Modelo
#'
#' Produz um relatorio estruturado de diferencas entre dois artefatos,
#' incluindo metadados e coeficientes.
#'
#' @param artifact_a lista, primeiro artefato de modelo
#' @param artifact_b lista, segundo artefato de modelo
#'
#' @return lista com campos:
#' \describe{
#'   \item{`id_usina_a`}{character, identificador da usina no artefato A}
#'   \item{`id_usina_b`}{character, identificador da usina no artefato B}
#'   \item{`metadata_diff`}{lista de diferencas de metadados}
#'   \item{`coefficient_diff`}{`data.table` com colunas `slot`, `a_artifact_a`,
#'     `a_artifact_b`, `diff`, `pct_change`}
#'   \item{`summary`}{lista com `mean_diff`, `max_diff`, `n_changed_slots`,
#'     `n_new_na`, `n_recovered`}
#' }
#'
#' @export
compare_artifacts <- function(artifact_a, artifact_b) {
    validate_comparison_input(artifact_a, "A")
    validate_comparison_input(artifact_b, "B")
    warn_cross_type(artifact_a, artifact_b)

    coeff_dt <- compare_coefficients(
        artifact_a$parametros, artifact_b$parametros
    )

    list(
        id_usina_a = artifact_a$id_usina,
        id_usina_b = artifact_b$id_usina,
        metadata_diff = compare_metadata(artifact_a, artifact_b),
        coefficient_diff = coeff_dt,
        summary = summarize_coefficient_diff(coeff_dt)
    )
}

#' Compara Dois Artefatos de Modelo a Partir de Arquivos
#'
#' Le dois arquivos RDS contendo artefatos e delega para
#' [compare_artifacts()].
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

    compare_artifacts(readRDS(path_a), readRDS(path_b))
}

#' Formata Relatorio de Comparacao de Artefatos
#'
#' Converte o resultado de [compare_artifacts()] em um relatorio
#' legivel por humanos, em portugues.
#'
#' @param comparison lista retornada por [compare_artifacts()]
#'
#' @return character vector com linhas do relatorio formatado
#'
#' @export
format_comparison <- function(comparison) {
    lines <- format_comparison_header(comparison)
    lines <- c(lines, format_comparison_metadata(comparison$metadata_diff))
    lines <- c(lines, format_comparison_summary(comparison))
    lines <- c(lines, format_comparison_top_diffs(comparison$coefficient_diff))
    lines
}

#' Compara Multiplos Artefatos de Modelo (Pairwise)
#'
#' Produz comparacoes pairwise para uma lista de 2 ou mais artefatos,
#' retornando um resultado por par.
#'
#' @param artifacts lista de artefatos de modelo
#' @param labels character vector de rotulos para cada artefato
#'
#' @return lista nomeada de comparacoes pairwise
#'
#' @export
compare_multiple_artifacts <- function(artifacts, labels = NULL) {
    n <- length(artifacts)
    if (n < 2L) {
        stop("Necessario pelo menos 2 artefatos para comparacao", call. = FALSE)
    }

    if (is.null(labels)) {
        labels <- paste0("artifact_", seq_len(n))
    }
    if (length(labels) != n) {
        stop("Numero de rotulos deve ser igual ao numero de artefatos",
            call. = FALSE)
    }

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

validate_comparison_input <- function(artifact, label) {
    if (!is.list(artifact)) {
        stop(sprintf("Artefato %s deve ser uma lista", label), call. = FALSE)
    }
    if (!"parametros" %in% names(artifact)) {
        stop(sprintf("Artefato %s deve conter campo 'parametros'", label),
            call. = FALSE)
    }
    if (!is.data.frame(artifact$parametros)) {
        stop(sprintf("Artefato %s: 'parametros' deve ser um data.frame",
                label), call. = FALSE)
    }
    invisible(TRUE)
}

has_metadata <- function(artifact) {
    "metadata" %in% names(artifact) && is.list(artifact$metadata)
}

warn_cross_type <- function(artifact_a, artifact_b) {
    if (!has_metadata(artifact_a) || !has_metadata(artifact_b)) {
        return(invisible(NULL))
    }
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
    invisible(NULL)
}

compute_metadata_field_diffs <- function(meta_a, meta_b) {
    fields <- setdiff(union(names(meta_a), names(meta_b)), "timestamp")
    diffs <- list()
    for (field in fields) {
        val_a <- meta_a[[field]]
        val_b <- meta_b[[field]]
        if (!identical(val_a, val_b)) {
            diffs[[length(diffs) + 1L]] <- list(
                field = field, value_a = val_a, value_b = val_b
            )
        }
    }
    diffs
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

    diffs <- compute_metadata_field_diffs(
        artifact_a$metadata, artifact_b$metadata
    )
    attr(diffs, "timestamp_a") <- artifact_a$metadata$timestamp
    attr(diffs, "timestamp_b") <- artifact_b$metadata$timestamp

    diffs
}

compare_coefficients <- function(params_a, params_b) {
    slots_a <- rownames(params_a)
    slots_b <- rownames(params_b)
    all_slots <- union(slots_a, slots_b)

    a_vals <- stats::setNames(rep(NA_real_, length(all_slots)), all_slots)
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
        a_artifact_a = unname(a_vals),
        a_artifact_b = unname(b_vals),
        diff = unname(diff_vals),
        pct_change = unname(pct_vals)
    )
}

summarize_coefficient_diff <- function(coeff_dt) {
    valid_both <- !is.na(coeff_dt$a_artifact_a) &
        !is.na(coeff_dt$a_artifact_b)
    abs_diff <- abs(coeff_dt$diff)

    stat_or_na <- function(fn) if (any(valid_both)) fn(abs_diff[valid_both]) else NA_real_

    list(
        mean_diff = stat_or_na(mean),
        max_diff = stat_or_na(max),
        n_changed_slots = sum(valid_both & coeff_dt$diff != 0, na.rm = TRUE),
        n_new_na = sum(!is.na(coeff_dt$a_artifact_a) & is.na(coeff_dt$a_artifact_b)),
        n_recovered = sum(is.na(coeff_dt$a_artifact_a) & !is.na(coeff_dt$a_artifact_b))
    )
}

format_comparison_header <- function(comparison) {
    fmt_ts <- function(ts) if (!is.null(ts)) format(ts, " (%Y-%m-%d %H:%M:%S)") else ""
    ts_a <- fmt_ts(attr(comparison$metadata_diff, "timestamp_a"))
    ts_b <- fmt_ts(attr(comparison$metadata_diff, "timestamp_b"))

    c(
        "Comparacao de Artefatos de Modelo",
        "==================================",
        sprintf("Usina A: %s%s", comparison$id_usina_a, ts_a),
        sprintf("Usina B: %s%s", comparison$id_usina_b, ts_b),
        ""
    )
}

format_comparison_metadata <- function(metadata_diff) {
    lines <- "Diferencas de Metadados:"

    if (!is.null(metadata_diff$note)) {
        lines <- c(lines, sprintf("  %s", metadata_diff$note))
    } else if (length(metadata_diff) == 0L) {
        lines <- c(lines, "  Nenhuma diferenca")
    } else {
        for (d in metadata_diff) {
            lines <- c(lines, sprintf("  %s: %s -> %s",
                    d$field, as.character(d$value_a), as.character(d$value_b)))
        }
    }

    c(lines, "")
}

format_comparison_summary <- function(comparison) {
    s <- comparison$summary
    n_total <- nrow(comparison$coefficient_diff)

    max_line <- if (!is.na(s$max_diff) && s$max_diff > 0) {
        max_slot <- comparison$coefficient_diff$slot[
            which.max(abs(comparison$coefficient_diff$diff))
        ]
        sprintf("  Diferenca maxima absoluta: %.4f (slot %s)", s$max_diff, max_slot)
    }

    c(
        "Resumo de Coeficientes:",
        sprintf("  Slots com mudanca: %d de %d", s$n_changed_slots, n_total),
        sprintf("  Diferenca media absoluta: %.4f", if (is.na(s$mean_diff)) 0 else s$mean_diff),
        max_line,
        sprintf("  Slots com NA novo: %d", s$n_new_na),
        sprintf("  Slots recuperados: %d", s$n_recovered),
        ""
    )
}

format_comparison_top_diffs <- function(coeff_dt) {
    valid_rows <- coeff_dt[!is.na(diff) & diff != 0]
    if (nrow(valid_rows) == 0L) return(character(0L))

    top_n <- min(5L, nrow(valid_rows))
    top <- valid_rows[order(-abs(diff))][seq_len(top_n)]

    lines <- "Maiores Diferencas:"
    for (i in seq_len(nrow(top))) {
        r <- top[i]
        pct_str <- if (!is.na(r$pct_change)) sprintf(" (%+.1f%%)", r$pct_change) else ""
        lines <- c(lines, sprintf("  %s  %.4f -> %.4f%s",
                r$slot, r$a_artifact_a, r$a_artifact_b, pct_str))
    }

    lines
}
