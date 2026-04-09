#' Carrega Estado de Retomada da Previsao
#'
#' Le o checkpoint de previsao e identifica usinas ja completadas cujos
#' resultados intermediarios existem em disco.
#'
#' @param args lista de argumentos do pipeline (deve conter `output` e
#'   `ids_usinas`)
#' @param provenance environment de proveniencia criado por
#'   [create_provenance()]
#'
#' @return lista com `provenance` (atualizado) e `completed` (character vector
#'   de IDs de usinas ja processadas)
#'
#' @seealso [read_checkpoint()], [get_pending_plants()],
#'   [read_plant_result()]
#'
#' @export
load_predict_resume_state <- function(args, provenance) {
    checkpoint <- read_checkpoint(args$output, args)
    if (is.null(checkpoint)) {
        return(list(provenance = provenance, completed = character(0L)))
    }
    candidate_completed <- setdiff(
        args$ids_usinas, get_pending_plants(checkpoint)
    )
    completed_plants <- Filter(function(iu) {
        !is.null(read_plant_result(iu, args$output))
    }, candidate_completed)
    for (iu in completed_plants) {
        update_plant_status(provenance, iu, "completed")
    }
    list(provenance = provenance, completed = completed_plants)
}

#' Funcao Principal de Consolidacao dos dados
#'
#' Executa o processamento completo de consistencia dos dados observados
#' para um conjunto de usinas, considerando diferentes fontes e modelos
#' em ordem de prioridade.
#'
#' @param args lista de argumentos necessarios para o processamento. Os campos
#'   esperados sao:
#'   - `artifact`: caminho onde artefatos adicionais serao armazenados.
#'   - `data_inicio`: string com a data inicial no formato `"yyyy-mm-dd"`.
#'   - `data_fim`: string com a data final no formato `"yyyy-mm-dd"`.
#'   - `fator_tolerancia_limite_superior_geracao`: fator de tolerancia.
#'   - `ids_usinas`: vetor com os IDs das usinas a serem processadas.
#'   - `input`: caminho para os dados de entrada.
#'   - `mode`: deve ser `"predict"`.
#'   - `ordem_prioridade_fontes`: fontes em ordem de prioridade.
#'   - `ordem_prioridade_modelosNWP`: modelos NWP em ordem de prioridade.
#'   - `output`: caminho para a pasta de saida.
#' @param parallel logico, se `TRUE` usa `future_lapply` para processar
#'   usinas em paralelo. Padrao `FALSE`.
#' @param resume logico, se `TRUE` busca um checkpoint valido e reprocessa
#'   apenas as usinas pendentes. Padrao `FALSE`.
#'
#' @return Nenhum valor e retornado. Os resultados sao gravados em arquivos.
#'
#' @seealso `organiza_resultados()`, [write_melhor_historico_geracao()],
#'   [setup_parallel_plan()],
#'   [write_checkpoint()], [read_checkpoint()], [write_plant_result()]
predict_main <- function(args, parallel = FALSE, resume = FALSE) {

    provenance <- create_provenance(args, "predict", parallel)
    metrics <- create_metrics(provenance$run_id, "predict")
    set_log_context(provenance$run_id, "predict")
    lg <- lgr::get_logger("mhpfv")
    completed_plants <- character(0L)

    if (resume) {
        state <- load_predict_resume_state(args, provenance)
        provenance <- state$provenance
        completed_plants <- state$completed
    }

    on.exit({
        if (provenance$status == "running") {
            finalize_provenance(provenance, "failed")
        }
        write_provenance(provenance, args$output)
        finalize_metrics(metrics)
        write_metrics(metrics, args$output)
        report <- build_health_report(provenance, metrics)
        write_health_report(report, args$output)
        clear_log_context()
    }, add = TRUE)

    conn <- conectamock_pfv(args$input)

    dt_usinas <- get_usinas(conn, id_usina = args$ids_usinas)

    dataset <- get_dataset(args, conn)

    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
    dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)

    v_usinas_pending <- setdiff(args$ids_usinas, completed_plants)

    resultados_new <- list()
    n_failed <- 0L

    if (length(v_usinas_pending) > 0L) {
        extra_args <- list(
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_mhg = dataset$mhg,
            dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            artifact_dir = args$artifact
        )

        if (parallel) {
            old_plan <- setup_parallel_plan()
            on.exit(reset_parallel_plan(old_plan), add = TRUE)
        }

        resultados_new <- run_plants(
            v_usinas_pending, processar_usina, extra_args,
            parallel = parallel, metrics = metrics, lg = lg
        )

        n_failed <- tally_predict_results(
            resultados_new, v_usinas_pending,
            provenance, metrics, lg, resume, args$output
        )
    }

    resultados <- collect_all_results(
        args$ids_usinas, v_usinas_pending, resultados_new, args$output
    )

    write_predict_output(resultados, args$ids_usinas, dt_usinas, args$output)

    final_status <- if (n_failed == 0L) "completed" else "failed"
    finalize_provenance(provenance, final_status)
    if (resume) cleanup_checkpoint(args$output)
}

get_dataset <- function(args, conn, mode = args$mode) {
    mode <- match.arg(mode, c("train", "predict"))
    janela <- paste0(args$janela[1], "/", args$janela[2])

    ger_obs <- get_geracao_observada(conn,
        id_usina = args$ids_usinas,
        data_hora_observacao = janela
    )
    corte <- get_corte_observado(conn,
        id_usina = args$ids_usinas,
        id_fonte_observacao = args$ordem_prioridade_fontes, data_hora_observacao = janela
    )
    irrad_prev <- get_irradiancia_prevista(conn,
        id_usina = args$ids_usinas,
        id_modelo_nwp = args$ordem_prioridade_modelosNWP, data_hora_previsao = janela
    )

    result <- list(
        ger_obs = ger_obs,
        corte = corte,
        irrad_prev = irrad_prev
    )

    if (mode == "predict") {
        result$mhg <- get_melhor_historico_geracao(conn, id_usina = args$ids_usinas)
        result$mhg_sem_cortes <- get_melhor_historico_geracao_sem_cortes(
            conn, id_usina = args$ids_usinas
        )
    }

    result
}

processar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_mhg,
    dt_mhg_sem_cortes, dt_irrad_prev_filt, dt_corte_obs, fonte,
    fator_tolerancia, artifact_dir, ...) {

    dad_usi <- dt_usinas[id_usina == iu]
    ger_usi <- dt_ger_obs[id_usina == iu]
    corte_obs <- dt_corte_obs[id_usina == iu]
    mhg <- dt_mhg[id_usina == iu]
    mhg_sc <- dt_mhg_sem_cortes[id_usina == iu]
    potencia_instalada <- dad_usi$capacidade_instalada_MW

    irrad_prev <- dt_irrad_prev_filt[id_usina == iu & passo_prev == "D+0"]

    irrad_prev <- interpolar_30min(irrad_prev)

    geracao_usina_consis <- consiste_geracao_unit(
        dados_usina = dad_usi,
        geracao_usina = ger_usi,
        corte_obs = corte_obs,
        ordem_prioridade = fonte,
        limite_dados = c(0, potencia_instalada * fator_tolerancia)
    )

    artifact <- pfvIO:::get_model_artifact(iu, artifact_dir)

    geracao_usina_preenchida <- preenche_geracao_unit(
        geracao_usina = geracao_usina_consis,
        irrad_prev = irrad_prev,
        mhg_prev = mhg,
        cortes = NULL,
        limite_dados = c(0, potencia_instalada * fator_tolerancia),
        model = artifact$model
    )

    datas <- lubridate::as_datetime(geracao_usina_consis$data_hora_observacao, tz = "UTC")

    dat_min <- min(datas, na.rm = TRUE)
    dat_max <- max(datas, na.rm = TRUE)

    geracao_usina_preenchida_sem_cortes <- preenche_geracao_unit(
        geracao_usina = geracao_usina_preenchida[
            data_hora_observacao >= dat_min & data_hora_observacao <= dat_max
        ],
        irrad_prev = irrad_prev,
        mhg_prev = mhg_sc,
        cortes = corte_obs,
        limite_dados = c(0, potencia_instalada * fator_tolerancia),
        model = artifact$model
    )

    # Garante que sem_cortes nunca seja menor que com_cortes
    idx_maior <- which(geracao_usina_preenchida$valor > geracao_usina_preenchida_sem_cortes$valor)
    geracao_usina_preenchida_sem_cortes[idx_maior, `:=`(
        valor = geracao_usina_preenchida[idx_maior, valor],
        status = geracao_usina_preenchida[idx_maior, status]
    )]

    list(
        com_cortes = geracao_usina_preenchida,
        sem_cortes = geracao_usina_preenchida_sem_cortes
    )
}

organiza_resultados <- function(resultados, v_usinas) {
    dt_com_cortes <- data.table::rbindlist(lapply(seq_along(resultados), function(i) {
        resultados[[i]]$com_cortes[, id_usina := v_usinas[i]]
    }), fill = TRUE)

    dt_sem_cortes <- data.table::rbindlist(lapply(seq_along(resultados), function(i) {
        resultados[[i]]$sem_cortes[, id_usina := v_usinas[i]]
    }), fill = TRUE)

    list(com_cortes = dt_com_cortes, sem_cortes = dt_sem_cortes)
}

run_plants <- function(v_usinas, fn, extra_args, parallel, metrics, lg) {
    if (parallel) {
        batch_start <- proc.time()[["elapsed"]]
        results <- future.apply::future_lapply(
            v_usinas, function(iu) {
                tryCatch(
                    do.call(fn, c(list(iu), extra_args)),
                    error = function(e) plant_error(iu, e)
                )
            }, future.seed = TRUE
        )
        batch_elapsed <- proc.time()[["elapsed"]] - batch_start
        est_per_plant <- round(batch_elapsed / length(v_usinas), 2L)
        for (iu in v_usinas) {
            record_plant_timing(metrics, iu, est_per_plant)
        }
    } else {
        results <- lapply(v_usinas, function(iu) {
            t0 <- proc.time()[["elapsed"]]
            result <- tryCatch(
                do.call(fn, c(list(iu), extra_args)),
                error = function(e) {
                    lg$error(
                        "Falha no processamento da usina %s: %s",
                        iu, conditionMessage(e)
                    )
                    plant_error(iu, e)
                }
            )
            record_plant_timing(
                metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L)
            )
            result
        })
    }
    results
}

tally_predict_results <- function(resultados, v_usinas, provenance, metrics,
    lg, resume, output_dir) {
    n_failed <- 0L
    n_total <- length(v_usinas)
    for (i in seq_along(v_usinas)) {
        iu <- v_usinas[i]
        if (is_plant_error(resultados[[i]])) {
            update_plant_status(provenance, iu, "failed")
            n_failed <- n_failed + 1L
            lg$error("Usina %s falhou: %s", iu, resultados[[i]]$error)
        } else {
            result <- resultados[[i]]
            n_rows <- nrow(result$com_cortes)
            n_na <- sum(is.na(result$com_cortes$valor))
            n_total_vals <- length(result$com_cortes$valor)
            record_plant_data_volume(
                metrics, iu,
                as.numeric(n_rows), as.numeric(n_na),
                as.numeric(n_total_vals)
            )
            update_plant_status(provenance, iu, "completed")
            if (resume) {
                write_plant_result(result, iu, output_dir)
                write_checkpoint(provenance, output_dir)
            }
        }
        lg$info("Usina %s processada (%d/%d)", iu, i, n_total)
    }
    n_failed
}

collect_all_results <- function(all_ids, pending_ids, new_results,
    output_dir) {
    lapply(all_ids, function(iu) {
        if (iu %in% pending_ids) {
            idx <- match(iu, pending_ids)
            r <- new_results[[idx]]
            if (is_plant_error(r)) return(NULL)
            r
        } else {
            read_plant_result(iu, output_dir)
        }
    })
}

write_predict_output <- function(resultados, ids_usinas, dt_usinas,
    output_dir) {
    valid_idx <- !vapply(resultados, is.null, logical(1L))
    resultados_valid <- resultados[valid_idx]
    usinas_valid <- ids_usinas[valid_idx]

    if (length(resultados_valid) == 0L) return(invisible(NULL))

    resultados_organizados <- organiza_resultados(
        resultados = resultados_valid,
        v_usinas = usinas_valid
    )

    geracao_com_cortes <- coloca_na_antes_inicio(
        dt = copy(resultados_organizados$com_cortes),
        dados_usina = dt_usinas
    )
    geracao_sem_cortes <- coloca_na_antes_inicio(
        dt = copy(resultados_organizados$sem_cortes),
        dados_usina = dt_usinas
    )

    write_melhor_historico_geracao(dt = geracao_com_cortes, output_dir = output_dir)
    write_melhor_historico_geracao_sem_cortes(dt = geracao_sem_cortes, output_dir = output_dir)
}
