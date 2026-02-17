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
#'
#' @return Nenhum valor e retornado pela funcao. Os resultados sao gravados
#'   diretamente em arquivos na pasta de saida especificada.
#'
#' @details
#' A funcao executa o treinamento do modelo para cada usina:
#'
#' 1. Leitura da configuracao e dados de entrada (usinas, geracao observada,
#'    modelos NWP, cortes, etc).
#' 2. Associacao das coordenadas NWP a cada usina e calculo do passo de
#'    previsao (computados uma unica vez antes do loop).
#' 3. Aplicacao da funcao `ajustar_usina()` para cada usina de forma
#'    individual (sequencial ou paralela), usando a estrategia de modelo
#'    fornecida.
#' 4. Gravacao sequencial dos artefatos de modelo em disco.
#'
#' Quando `parallel = TRUE`, o plano de execucao paralela e configurado via
#' [setup_parallel_plan()] e restaurado ao final com [reset_parallel_plan()].
#'
#' @seealso [fit_model()], [linear_regression_strategy()],
#'   [setup_parallel_plan()]
#'
#' @export
train_main <- function(args, strategy = linear_regression_strategy(),
    parallel = FALSE) {

    conn <- conectamock_pfv(args$input)

    v_usinas <- args$ids_usinas
    dt_usinas <- get_usinas(conn, id_usina = v_usinas)

    dataset <- get_dataset(args, conn)

    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
    dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)

    if (parallel) {
        old_plan <- setup_parallel_plan()
        on.exit(reset_parallel_plan(old_plan), add = TRUE)
        models <- future.apply::future_lapply(v_usinas, ajustar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy,
            future.seed = TRUE
        )
    } else {
        models <- lapply(v_usinas, ajustar_usina,
            dt_usinas = dt_usinas,
            dt_ger_obs = dataset$ger_obs,
            dt_irrad_prev_filt = dt_irrad_prev_filt,
            dt_corte_obs = dataset$corte,
            fonte = args$ordem_prioridade_fontes,
            fator_tolerancia = args$fator_tolerancia_limite_superior_geracao,
            strategy = strategy
        )
    }

    lapply(seq_along(v_usinas), function(i) {
        write_model_artifact(models[[i]], v_usinas[i], args$artifact)
    })
}

ajustar_usina <- function(iu, dt_usinas, dt_ger_obs, dt_irrad_prev_filt,
    dt_corte_obs, fonte, fator_tolerancia,
    strategy = linear_regression_strategy(), ...) {
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

    list(id_usina = iu, parametros = regressoes)
}


#' Ajusta Regressao Linear entre Geracao Observada e Irradiacao Prevista
#'
#' Estima coeficientes de regressao linear para cada horario de meia em meia hora,
#' usando dados de geracao observada e irradiacao prevista.
#'
#' @param dty data.table com dados de geracao observada. Deve conter as colunas:
#'   \itemize{
#'     \item \code{id_usina}: identificador da usina.
#'     \item \code{data_hora_observacao}: data e hora da geracao (classe POSIXct).
#'     \item \code{valor}: valor numerico da geracao.
#'   }
#' @param dtx data.table com dados de irradiacao prevista. Deve conter as colunas:
#'   \itemize{
#'     \item \code{id_usina}: identificador da usina.
#'     \item \code{data_hora_previsao}: data e hora da irradiacao (classe POSIXct).
#'     \item \code{valor}: valor numerico da irradiacao.
#'   }
#' @param dty_bruta data.table com dados de geracao observada bruta. Deve conter as colunas:
#'   \itemize{
#'     \item \code{id_usina}: identificador da usina.
#'     \item \code{data_hora_observacao}: data e hora da geracao (classe POSIXct).
#'     \item \code{valor}: valor numerico da geracao.
#'   }
#'
#' @return Um data.frame com os coeficientes de regressao por horario, com:
#'   \itemize{
#'     \item \code{a}: coeficiente angular da regressao (inclinacao da reta).
#'     \item \code{b}: coeficiente linear, sempre zero neste ajuste.
#'     \item Nomes das linhas indicando o horario no formato "HH:MM".
#'   }
#'
#' @details
#' A funcao percorre os horarios do dia entre 05:00 e 18:30 com passos de 30 minutos.
#' Para cada horario, filtra os dados de geracao e irradiacao correspondentes e realiza um
#' ajuste linear sem intercepto (\code{lm(y ~ x + 0)}). Apenas pares com mais de 5 observacoes validas
#' sao considerados. Quando ha dados insuficientes, o coeficiente angular e definido como zero.
#'
#' Valores iguais a zero sao tratados como ausentes (NA) antes do ajuste.
#'
#' @seealso substitui_por_estimativas

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
