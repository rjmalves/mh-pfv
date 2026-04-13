#' Cria Registro de Metricas de Execucao
#'
#' @param run_id character escalar, identificador da execucao
#' @param mode character escalar, `"train"` ou `"predict"`
#'
#' @return environment com estrutura de metricas vazia
create_metrics <- function(run_id, mode) {
    stopifnot(
        is.character(run_id), length(run_id) == 1L,
        is.character(mode), length(mode) == 1L
    )
    m <- new.env(parent = emptyenv())
    m$run_id <- run_id
    m$mode <- mode
    m$created_at <- NULL
    m$pipeline <- list()
    m$plants <- new.env(parent = emptyenv())
    m
}

#' Registra Tempo de Processamento de Uma Usina
#'
#' @param metrics environment de metricas criado por [create_metrics()]
#' @param id_usina character escalar, identificador da usina
#' @param duration_secs numeric escalar, duracao em segundos de parede
#'
#' @return invisivel, environment de metricas (mutado in-place)
record_plant_timing <- function(metrics, id_usina, duration_secs) {
    stopifnot(
        is.environment(metrics),
        is.character(id_usina), length(id_usina) == 1L,
        is.numeric(duration_secs), length(duration_secs) == 1L
    )
    if (is.null(metrics$plants[[id_usina]])) {
        metrics$plants[[id_usina]] <- list()
    }
    metrics$plants[[id_usina]]$duration_seconds <- duration_secs
    invisible(metrics)
}

#' Registra Volume de Dados Processados de Uma Usina
#'
#' @param metrics environment de metricas criado por [create_metrics()]
#' @param id_usina character escalar, identificador da usina
#' @param n_rows numeric escalar, total de linhas processadas
#' @param n_na numeric escalar, numero de valores `NA`
#' @param n_total numeric escalar, denominador para calculo da taxa de NA
#'
#' @return invisivel, environment de metricas (mutado in-place)
record_plant_data_volume <- function(metrics, id_usina, n_rows, n_na, n_total) {
    stopifnot(
        is.environment(metrics),
        is.character(id_usina), length(id_usina) == 1L,
        is.numeric(n_rows), length(n_rows) == 1L,
        is.numeric(n_na), length(n_na) == 1L,
        is.numeric(n_total), length(n_total) == 1L
    )
    if (is.null(metrics$plants[[id_usina]])) {
        metrics$plants[[id_usina]] <- list()
    }
    na_rate <- if (n_total > 0) n_na / n_total else NA_real_
    metrics$plants[[id_usina]]$data_volume <- list(
        n_rows = as.integer(n_rows),
        n_na = as.integer(n_na),
        na_rate = round(na_rate, 4L)
    )
    invisible(metrics)
}

#' Registra Qualidade do Modelo Ajustado para Uma Usina
#'
#' Extrai `n_slots` e `n_valid_slots` dos metadados do artefato e os adiciona
#' ao registro da usina.
#'
#' @param metrics environment de metricas criado por [create_metrics()]
#' @param id_usina character escalar, identificador da usina
#' @param metadata lista de metadados do artefato (de [model_metadata()])
#'
#' @return invisivel, environment de metricas (mutado in-place)
record_model_quality <- function(metrics, id_usina, metadata) {
    stopifnot(
        is.environment(metrics),
        is.character(id_usina), length(id_usina) == 1L,
        is.list(metadata)
    )
    if (is.null(metrics$plants[[id_usina]])) {
        metrics$plants[[id_usina]] <- list()
    }
    metrics$plants[[id_usina]]$model_quality <- list(
        n_slots = metadata$n_slots,
        n_valid_slots = metadata$n_valid_slots
    )
    invisible(metrics)
}

#' Finaliza Metricas com Agregados do Pipeline
#'
#' Computa estatisticas agregadas das metricas por usina e preenche
#' `metrics$pipeline`. Campos de duracao sao `NA_real_` quando nenhuma
#' usina tem `duration_seconds` registrado.
#'
#' @param metrics environment de metricas criado por [create_metrics()]
#'
#' @return invisivel, environment de metricas (mutado in-place)
finalize_metrics <- function(metrics) {
    stopifnot(is.environment(metrics))

    plant_list <- as.list(metrics$plants)
    durations <- vapply(
        plant_list,
        function(p) {
            if (!is.null(p$duration_seconds)) p$duration_seconds else NA_real_
        },
        numeric(1L)
    )
    valid_durations <- durations[!is.na(durations)]
    n_completed <- length(valid_durations)

    metrics$created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    metrics$pipeline <- list(
        n_plants = length(plant_list),
        n_plants_completed = n_completed,
        mean_plant_duration_seconds = if (n_completed > 0L)
            round(mean(valid_durations), 2L) else NA_real_,
        max_plant_duration_seconds = if (n_completed > 0L)
            round(max(valid_durations), 2L) else NA_real_,
        min_plant_duration_seconds = if (n_completed > 0L)
            round(min(valid_durations), 2L) else NA_real_
    )
    invisible(metrics)
}

#' Converte Metricas de Ambiente para Lista
#'
#' Serializa um registro de metricas (environment) para lista plain,
#' adequado para conversao em JSON.
#'
#' @param metrics environment de metricas
#'
#' @return lista com todos os campos, `plants` tambem como lista
metrics_as_list <- function(metrics) {
    out <- as.list(metrics)
    out$plants <- as.list(metrics$plants)
    out
}

#' Escreve Metricas em JSON
#'
#' Serializa as metricas como `metrics-{run_id}.json` no diretorio informado.
#' Falhas de I/O geram apenas aviso no log e nunca interrompem o pipeline.
#'
#' @param metrics environment de metricas finalizado por [finalize_metrics()]
#' @param output_dir character, diretorio de saida
#'
#' @return caminho do arquivo escrito (invisivelmente)
write_metrics <- function(metrics, output_dir) {
    lg <- lgr::get_logger("mhpfv")
    filename <- paste0("metrics-", metrics$run_id, ".json")
    filepath <- file.path(output_dir, filename)

    tryCatch({
        if (!dir.exists(output_dir)) {
            dir.create(output_dir, recursive = TRUE)
        }
        json_str <- jsonlite::toJSON(
            metrics_as_list(metrics),
            pretty = TRUE, auto_unbox = TRUE, null = "null"
        )
        writeLines(json_str, filepath)
        lg$info("Metricas escritas em: %s", filepath)
    }, error = function(e) {
        lg$warn(
            "Falha ao escrever metricas em '%s': %s",
            filepath, conditionMessage(e)
        )
    })

    invisible(filepath)
}
