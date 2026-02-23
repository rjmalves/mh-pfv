#' Funcao Principal de Consolidacao dos dados
#'
#' Executa o processamento completo de consistencia dos dados observados para um conjunto de usinas,
#' considerando diferentes fontes e modelos em ordem de prioridade.
#'
#' @param args lista de argumentos necessarios para o processamento. Os campos
#'   esperados sao:
#'   - `artifact`: caminho onde artefatos adicionais serao armazenados.
#'   - `data_inicio`: string com a data inicial no formato `"yyyy-mm-dd"`.
#'   - `data_fim`: string com a data final no formato `"yyyy-mm-dd"`.
#'   - `fator_tolerancia_limite_superior_geracao`: fator de tolerancia aplicado
#'     ao limite superior de geracao observada.
#'   - `ids_usinas`: vetor com os IDs das usinas a serem processadas.
#'   - `input`: caminho para os dados de entrada (SCADA, NWP, cortes, etc.).
#'   - `mode`: deve ser `"predict"`.
#'   - `ordem_prioridade_fontes`: fontes de dados em ordem de prioridade.
#'   - `ordem_prioridade_modelosNWP`: modelos NWP em ordem de prioridade.
#'   - `output`: caminho para a pasta de saida.
#' @param strategy objeto [new_model_strategy()] definindo o tipo de modelo a
#'   usar na previsao. Por padrao usa [linear_regression_strategy()], mantendo
#'   comportamento identico ao original.
#' @param parallel logico, se `TRUE` usa `future_lapply` para processar
#'   usinas em paralelo. Padrao `FALSE` para compatibilidade.
#' @param resume logico, se `TRUE` busca um checkpoint valido no diretorio
#'   de saida e reprocessa apenas as usinas pendentes. Resultados intermediarios
#'   de usinas concluidas sao carregados do disco. Padrao `FALSE`.
#'
#' @return Nenhum valor e retornado. Os resultados sao gravados em arquivos na
#'   pasta de saida especificada.
#'
#' @seealso `organiza_resultados()`, [write_melhor_historico_geracao()],
#'   [linear_regression_strategy()], [setup_parallel_plan()],
#'   [write_checkpoint()], [read_checkpoint()], [write_plant_result()]
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
        provenance <- update_plant_status(provenance, iu, "completed")
    }
    list(provenance = provenance, completed = completed_plants)
}

predict_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE, resume = FALSE) {

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
            provenance <- finalize_provenance(provenance, "failed")
        }
        write_provenance(provenance, args$output)
        metrics <- finalize_metrics(metrics)
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

    if (length(v_usinas_pending) > 0L) {
        apply_args <- list(v_usinas_pending, processar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_mhg = dataset$mhg,
            dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            artifact_dir = args$artifact,
            strategy = strategy
        )

        if (parallel) {
            old_plan <- setup_parallel_plan()
            on.exit(reset_parallel_plan(old_plan), add = TRUE)
            batch_start <- proc.time()[["elapsed"]]
            resultados_new <- do.call(future.apply::future_lapply,
                c(apply_args, list(future.seed = TRUE)))
            batch_elapsed <- proc.time()[["elapsed"]] - batch_start
            est_per_plant <- round(batch_elapsed / length(v_usinas_pending), 2L)
            for (iu in v_usinas_pending) {
                metrics <- record_plant_timing(metrics, iu, est_per_plant)
            }
        } else {
            extra_args <- apply_args[-(1L:2L)]
            resultados_new <- lapply(v_usinas_pending, function(iu) {
                t0 <- proc.time()[["elapsed"]]
                result <- do.call(processar_usina, c(list(iu), extra_args))
                # <<- necessario para atualizar metrics no escopo da funcao pai
                metrics <<- record_plant_timing(
                    metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L)
                )
                result
            })
        }

        n_total <- length(v_usinas_pending)
        for (i in seq_along(v_usinas_pending)) {
            result <- resultados_new[[i]]
            n_rows <- nrow(result$com_cortes)
            n_na <- sum(is.na(result$com_cortes$valor))
            n_total_vals <- length(result$com_cortes$valor)
            metrics <- record_plant_data_volume(
                metrics, v_usinas_pending[i],
                as.numeric(n_rows), as.numeric(n_na), as.numeric(n_total_vals)
            )
            # <<- necessario para atualizar provenance no escopo da funcao pai
            provenance <<- update_plant_status(
                provenance, v_usinas_pending[i], "completed"
            )
            if (resume) {
                write_plant_result(
                    result, v_usinas_pending[i], args$output
                )
                write_checkpoint(provenance, args$output)
            }
            lg$info("Usina %s concluida (%d/%d)", v_usinas_pending[i], i, n_total)
        }
    }

    resultados <- lapply(args$ids_usinas, function(iu) {
        if (iu %in% v_usinas_pending) {
            resultados_new[[match(iu, v_usinas_pending)]]
        } else {
            read_plant_result(iu, args$output)
        }
    })

    resultados_organizados <- organiza_resultados(
        resultados = resultados,
        v_usinas = args$ids_usinas
    )

    geracao_usina_preenchida_com_cortes <- coloca_na_antes_inicio(
        dt = copy(resultados_organizados$com_cortes),
        dados_usina = dt_usinas
    )

    geracao_usina_preenchida_sem_cortes <- coloca_na_antes_inicio(
        dt = copy(resultados_organizados$sem_cortes),
        dados_usina = dt_usinas
    )

    write_melhor_historico_geracao(
        dt = geracao_usina_preenchida_com_cortes,
        output_dir = args$output
    )

    write_melhor_historico_geracao_sem_cortes(
        dt = geracao_usina_preenchida_sem_cortes,
        output_dir = args$output
    )

    provenance <- finalize_provenance(provenance, "completed")
    if (resume) cleanup_checkpoint(args$output)
}

get_dataset <- function(args, conn) {
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
    mhg <- get_melhor_historico_geracao(conn, id_usina = args$ids_usinas)
    mhg_sem_cortes <- get_melhor_historico_geracao_sem_cortes(conn, id_usina = args$ids_usinas)

    list(
        ger_obs = ger_obs,
        corte = corte,
        irrad_prev = irrad_prev,
        mhg = mhg,
        mhg_sem_cortes = mhg_sem_cortes
    )
}

processar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_mhg,
    dt_mhg_sem_cortes, dt_irrad_prev_filt, dt_corte_obs, fonte,
    fator_tolerancia, artifact_dir,
    strategy = linear_regression_strategy(), ...) {

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

    model <- pfvIO:::get_model_artifact(iu, artifact_dir)

    geracao_usina_preenchida <- preenche_geracao_unit(
        geracao_usina = geracao_usina_consis,
        irrad_prev = irrad_prev,
        mhg_prev = mhg,
        cortes = NULL,
        limite_dados = c(0, potencia_instalada * fator_tolerancia),
        model = model,
        strategy = strategy
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
        model = model,
        strategy = strategy
    )

    # Garante que sem_cortes nunca seja menor que com_cortes
    idx_maior <- geracao_usina_preenchida$valor > geracao_usina_preenchida_sem_cortes$valor
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
