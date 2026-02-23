#' Funcao Principal de Treinamento dos Modelos para Consistencia dos Dados
#'
#' Executa o treinamento dos modelos para consistencia dos dados observados
#' para um conjunto de usinas.
#'
#' @param args lista de argumentos necessarios para o processamento. Os campos
#'   esperados sao:
#'   - `artifact`: caminho onde artefatos adicionais serao armazenados.
#'   - `data_inicio`: string com a data inicial no formato `"yyyy-mm-dd"`,
#'     indicando o inicio do periodo de analise.
#'   - `data_fim`: string com a data final no formato `"yyyy-mm-dd"`,
#'     indicando o fim do periodo de analise.
#'   - `fator_tolerancia_limite_superior_geracao`: valor numerico que define
#'     o fator de tolerancia aplicado ao limite superior de geracao observada.
#'   - `ids_usinas`: vetor com os IDs das usinas a serem processadas. Se
#'     `NULL`, todas as usinas disponiveis serao utilizadas.
#'   - `input`: caminho para a pasta onde estao localizados os dados de
#'     entrada (ex: dados de SCADA, modelos NWP, cortes, etc.).
#'   - `mode`: string que define o modo de operacao. Deve ser `"train"` para
#'     rodar o treinamento dos modelos.
#'   - `ordem_prioridade_modelosNWP`: string com os nomes dos modelos NWP
#'     separados por virgula, em ordem de prioridade.
#' @param strategy objeto [new_model_strategy()] definindo o tipo de modelo a
#'   ajustar. Por padrao usa [linear_regression_strategy()], mantendo
#'   comportamento identico ao original.
#' @param parallel logico, se `TRUE` usa `future_lapply` para processar
#'   usinas em paralelo. Padrao `FALSE` para compatibilidade.
#' @param resume logico, se `TRUE` busca um checkpoint valido no diretorio
#'   de artefatos e reprocessa apenas as usinas pendentes. Padrao `FALSE`.
#'
#' @return Nenhum valor e retornado pela funcao. Os resultados sao gravados
#'   diretamente em arquivos na pasta de saida especificada.
#'
#' @seealso [fit_model()], [linear_regression_strategy()],
#'   [setup_parallel_plan()], [write_checkpoint()], [read_checkpoint()]
#'
#' @export
load_train_resume_state <- function(args, provenance) {
    checkpoint <- read_checkpoint(args$artifact, args)
    if (is.null(checkpoint)) {
        return(list(provenance = provenance, completed = character(0L)))
    }
    completed_plants <- setdiff(
        args$ids_usinas, get_pending_plants(checkpoint)
    )
    for (iu in completed_plants) {
        provenance <- update_plant_status(provenance, iu, "completed")
    }
    list(provenance = provenance, completed = completed_plants)
}

train_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE, resume = FALSE) {

    provenance <- create_provenance(args, "train", parallel)
    metrics <- create_metrics(provenance$run_id, "train")
    set_log_context(provenance$run_id, "train")
    lg <- lgr::get_logger("mhpfv")
    completed_plants <- character(0L)

    if (resume) {
        state <- load_train_resume_state(args, provenance)
        provenance <- state$provenance
        completed_plants <- state$completed
    }

    on.exit({
        if (provenance$status == "running") {
            provenance <- finalize_provenance(provenance, "failed")
        }
        write_provenance(provenance, args$artifact)
        metrics <- finalize_metrics(metrics)
        write_metrics(metrics, args$artifact)
        report <- build_health_report(provenance, metrics)
        write_health_report(report, args$artifact)
        clear_log_context()
    }, add = TRUE)

    v_usinas <- setdiff(args$ids_usinas, completed_plants)

    if (length(v_usinas) == 0L) {
        provenance <- finalize_provenance(provenance, "completed")
        cleanup_checkpoint(args$artifact)
        return(invisible(NULL))
    }

    conn <- conectamock_pfv(args$input)

    dt_usinas <- get_usinas(conn, id_usina = args$ids_usinas)

    dataset <- get_dataset(args, conn)

    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
    dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)

    if (parallel) {
        old_plan <- setup_parallel_plan()
        on.exit(reset_parallel_plan(old_plan), add = TRUE)
        batch_start <- proc.time()[["elapsed"]]
        models <- future.apply::future_lapply(v_usinas, ajustar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            config = args,
            future.seed = TRUE
        )
        batch_elapsed <- proc.time()[["elapsed"]] - batch_start
        est_per_plant <- round(batch_elapsed / length(v_usinas), 2L)
        for (iu in v_usinas) {
            metrics <- record_plant_timing(metrics, iu, est_per_plant)
        }
    } else {
        models <- lapply(v_usinas, function(iu) {
            t0 <- proc.time()[["elapsed"]]
            result <- ajustar_usina(iu,
                dt_usinas = dt_usinas,
                dt_ger_obs = dataset$ger_obs,
                dt_irrad_prev_filt = dt_irrad_prev_filt,
                dt_corte_obs = dataset$corte,
                fonte = args$ordem_prioridade_fontes,
                fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
                strategy = strategy,
                config = args
            )
            # <<- necessario para atualizar metrics no escopo da funcao pai
            metrics <<- record_plant_timing(
                metrics, iu, round(proc.time()[["elapsed"]] - t0, 2L)
            )
            result
        })
    }

    n_total <- length(v_usinas)
    lapply(seq_along(v_usinas), function(i) {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
        # <<- necessario para atualizar provenance e metrics no escopo pai
        provenance <<- update_plant_status(
            provenance, v_usinas[i], "completed"
        )
        if ("metadata" %in% names(models[[i]])) {
            metrics <<- record_model_quality(
                metrics, v_usinas[i], models[[i]]$metadata
            )
        }
        if (resume) write_checkpoint(provenance, args$artifact)
        lg$info("Usina %s concluida (%d/%d)", v_usinas[i], i, n_total)
    })

    provenance <- finalize_provenance(provenance, "completed")
    if (resume) cleanup_checkpoint(args$artifact)
}

ajustar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_irrad_prev_filt,
    dt_corte_obs, fonte, fator_tolerancia,
    strategy = linear_regression_strategy(), config = list(), ...) {
    dad_usi <- dt_usinas[id_usina == iu]
    ger_usi <- dt_ger_obs[id_usina == iu]
    corte_obs <- dt_corte_obs[id_usina == iu]
    potencia_instalada <- dad_usi$capacidade_instalada_MW

    irrad_prev <- dt_irrad_prev_filt[id_usina == iu & passo_prev == "D+0"]
    irrad_prev <- interpolar_30min(irrad_prev)

    geracao_usina_selec <- consiste_geracao_unit(
        dados_usina = dad_usi,
        geracao_usina = ger_usi,
        corte_obs = corte_obs,
        ordem_prioridade = fonte,
        limite_dados = c(0, potencia_instalada * fator_tolerancia)
    )

    geracao_usina_selec[valor == 999, valor := NA]
    irrad_prev[valor == 999, valor := NA]
    geracao_usina_bruta <- copy(geracao_usina_selec)

    if (!is.null(corte_obs)) {
        geracao_usina_selec <- aplica_cortes_em_geracao(
            dt_geracao_usina = copy(geracao_usina_selec),
            dt_cortes = copy(corte_obs)
        )
    }

    regressoes <- fit_model(strategy,
        dty = copy(geracao_usina_selec),
        dtx = copy(irrad_prev),
        dty_bruta = geracao_usina_bruta
    )

    build_model_artifact(iu, regressoes, strategy, config)
}

ajusta_regressao_ger_irrad <- function(dty, dtx, dty_bruta) {
    dty[valor == 0, valor := NA]
    dtx[valor == 0, valor := NA]
    dty_bruta[valor == 0, valor := NA]

    horas_meia_hora <- seq(5.0, 18.5, by = 0.5)

    angulares <- c()
    lineares <- c()
    nomes_linhas <- c()

    for (h in horas_meia_hora) {
        hora_inteira <- floor(h)
        minuto <- ifelse((h - hora_inteira) == 0.5, 30, 0)

        dty_f <- dty[hour(data_hora_observacao) == hora_inteira &
                minute(data_hora_observacao) == minuto]

        dtx_fn <- dtx[hour(data_hora_previsao) == hora_inteira &
                minute(data_hora_previsao) == minuto]

        dtx_f <- dtx_fn[dty_f, on = .(id_usina, data_hora_previsao = data_hora_observacao), nomatch = 0]
        dty_f <- dty_f[dtx_f, on = .(id_usina, data_hora_observacao = data_hora_previsao), nomatch = 0]

        dados_validos <- complete.cases(dty_f$valor, dtx_f$valor)
        if (sum(dados_validos) < 10) {
            dty_f <- dty_bruta[hour(data_hora_observacao) == hora_inteira &
                    minute(data_hora_observacao) == minuto]
            q60 <- quantile(dty_f$valor, probs = 0.7, na.rm = TRUE)
            dty_f[valor < q60, valor := NA]

            dtx_fn <- dtx[hour(data_hora_previsao) == hora_inteira &
                    minute(data_hora_previsao) == minuto]

            dtx_f <- dtx_fn[dty_f, on = .(id_usina, data_hora_previsao = data_hora_observacao), nomatch = 0]
            dty_f <- dty_f[dtx_f, on = .(id_usina, data_hora_observacao = data_hora_previsao), nomatch = 0]
        }


        if (nrow(dty_f) > 5 && nrow(dty_f) == nrow(dtx_f)) {
            dados_validos <- complete.cases(dty_f$valor, dtx_f$valor)
            if (sum(dados_validos) > 5) {
                y <- dty_f$valor[dados_validos]
                x <- dtx_f$valor[dados_validos]

                mod <- lm(y ~ x + 0)
                a <- coef(mod)[1]
                b <- 0

                angulares <- c(angulares, a)
                lineares <- c(lineares, b)
                hora_txt <- sprintf("%02d:%02d", hora_inteira, minuto)
                nomes_linhas <- c(nomes_linhas, hora_txt)
            } else {
                angulares <- c(angulares, NA)
                lineares <- c(lineares, NA)
                hora_txt <- sprintf("%02d:%02d", hora_inteira, minuto)
                nomes_linhas <- c(nomes_linhas, hora_txt)
            }
        }
    }

    data.frame(a = angulares, b = lineares, row.names = nomes_linhas)
}
