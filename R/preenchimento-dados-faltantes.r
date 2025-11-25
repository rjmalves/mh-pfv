#' Preenche Serie de Geracao para com Estimativas
#'
#' Realiza o preenchimento de valores ausentes na geracao observada de uma usina, utilizando irradiacao prevista corrigida por regressao linear.
#'
#' @param geracao_usina data.table com os dados de geracao observada da usina. Deve conter colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor}.
#' @param irrad_prev data.table com previsao de irradiancia. Deve conter colunas \code{id_usina}, \code{data_hora_previsao} e \code{valor}.
#' @param mhg_prev data.table com melhores historicos de geracao anteriores. Deve conter colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor}.
#' @param cortes data.table com registros de cortes (opcional). Deve conter colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor} (1 para corte).
#' @param limite_dados Vetor numerico de comprimento 2 com os limites inferior e superior permitidos para valores de geracao.
#'
#' @return Um data.table com a serie de geracao completa, com valores preenchidos, cortes aplicados, e horarios extremos zerados onde nao ha geracao valida.
#'
#' @details
#' A funcao executa o seguinte fluxo:
#' \enumerate{
#'   \item Substitui o valor 999 por NA nos dados de geracao e irradiancia.
#'   \item Aplica cortes na serie de geracao, se fornecido.
#'   \item Ajusta modelos de regressao linear por horario com base na irradiacao prevista.
#'   \item Substitui valores ausentes da geracao pelas estimativas resultantes da regressao.
#'   \item Verifica valores ausentes no MHG e faz a combinacao com os dados novos.
#'   \item Zera valores em horarios fora do intervalo com geracao valida.
#' }
#'
#' @examples
#' # Exemplo simplificado - veja funcoes auxiliares para gerar dados simulados realistas
#'
#' library(data.table)
#'
#' # Dados base com multiplos dias para horario fixo (06:00)
#' dias <- seq(from = as.Date("2025-01-01"), by = "1 day", length.out = 10)
#' horarios <- as.POSIXct(paste(dias, "06:00:00"))
#'
#' # Dados de geracao
#' geracao_usina <- data.table(
#'     id_usina = "U1",
#'     id_fonte_observacao = "PI",
#'     data_hora_observacao = horarios,
#'     valor = c(NA, 2, 4, 6, 8, 10, 12, 14, 16, 18),
#'     status = c(NA, rep(1, 9))
#' )
#'
#' # Dados de irradiancia
#' irrad_prev <- data.table(
#'     id_usina = "U1",
#'     data_hora_previsao = horarios,
#'     valor = seq(10, 100, by = 10)
#' )
#'
#' # Dados do melhor historico de rodadas anteriores
#' mhg_prev <- data.table(
#'     id_usina = "U1",
#'     id_fonte_observacao = "PI",
#'     data_hora_observacao = horarios,
#'     valor = rep(1, 10),
#'     status = c(NA, rep(1, 9))
#' )
#'
#' cortes <- NULL
#' limite_dados <- c(0, 25)
#'
#' resultado <- preenche_geracao_unit(
#'     geracao_usina = copy(geracao_usina),
#'     irrad_prev = copy(irrad_prev),
#'     mhg_prev = copy(mhg_prev),
#'     cortes = cortes,
#'     limite_dados = limite_dados
#' )
#'
#' @seealso ajusta_regressao_ger_irrad, substitui_por_estimativas, aplica_cortes_em_geracao, combina_dados_tempo, zera_horarios_extremos

preenche_geracao_unit <- function(geracao_usina, irrad_prev, mhg_prev, cortes, limite_dados, model) {
    geracao_usina[valor == 999, valor := NA]
    irrad_prev[valor == 999, valor := NA]
    geracao_usina_bruta <- copy(geracao_usina)

    # ajusta modelo de regressao linear
    if (!is.null(cortes)) {
        geracao_usina <- aplica_cortes_em_geracao(
            dt_geracao_usina = copy(geracao_usina),
            dt_cortes = copy(cortes)
        )
    }

    # # ajusta modelo de regressao linear
    # regressoes <- ajusta_regressao_ger_irrad(
    #     dty = copy(geracao_usina),
    #     dtx = copy(irrad_prev),
    #     dty_bruta = geracao_usina_bruta
    # )

    # preenche dados faltantes pela estimativa
    geracao_usina_completo <- substitui_por_estimativas(
        df_ger_usi = copy(geracao_usina),
        df_irrad_prev = copy(irrad_prev),
        regressoes = model[[2]],
        lim_dados = limite_dados
    )

    # checa valores faltantes do MHG
    mhg_prev <- checa_valores_faltantes(
        dt = mhg_prev
    )

    # faz um merge entre mhg historico anterior com a parte nova
    resultado_combinado <- combina_dados_tempo(
        dt1 = mhg_prev,
        dt2 = geracao_usina_completo
    )

    # zera posicoes de horarios sem geracao
    geracao_usina_completo_final <- zera_horarios_extremos(
        df_ger_usi = copy(resultado_combinado)
    )

    return(geracao_usina_completo_final)
}



# AUXILIARES ---------------------------------------------------------------------------------------



#' Substitui Valores Ausentes por Estimativas com Base em Irradiacao Prevista
#'
#' Preenche valores ausentes na geracao observada utilizando estimativas calculadas a partir de previsoes de irradiacao e coeficientes de regressao.
#'
#' @param df_ger_usi data.table com a geracao observada da usina. Deve conter as colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor}.
#' @param df_irrad_prev data.table com a irradiacao prevista. Deve conter as colunas \code{id_usina}, \code{data_hora_previsao} e \code{valor}.
#' @param regressoes Data frame ou data.table com os coeficientes de regressao para cada horario. Deve conter uma coluna \code{a} e nomes das linhas como \code{HH:MM}.
#' @param lim_dados Vetor numerico de comprimento 2 com os limites inferior e superior permitidos para os valores de geracao. Valores fora desse intervalo serao substituidos por NA.
#'
#' @return O mesmo data.table \code{df_ger_usi}, com os valores originalmente ausentes preenchidos pelas estimativas, e a coluna \code{status} atualizada para 4 nos casos de substituicao.
#'
#' @details
#' A funcao realiza os seguintes passos:
#' \enumerate{
#'   \item Extrai a hora:minuto da previsao de irradiacao.
#'   \item Junta os dados de irradiacao com os coeficientes de regressao com base na hora.
#'   \item Calcula a geracao estimada como \code{ger_est = a * irradiacao}.
#'   \item Substitui valores NA em \code{df_ger_usi} pelas estimativas, quando disponiveis.
#'   \item Atualiza o campo \code{status} para 4 onde a substituicao ocorreu.
#'   \item Aplica filtros finais para garantir que os valores estejam dentro dos limites definidos.
#' }
#'
#' @examples
#' library(data.table)
#'
#' df_ger <- data.table(
#'     id_usina = "U1",
#'     data_hora_observacao = as.POSIXct(c("2025-01-01 12:00", "2025-01-01 12:30")),
#'     valor = c(NA, 5),
#'     status = c(NA, 1)
#' )
#'
#' df_irrad <- data.table(
#'     id_usina = "U1",
#'     data_hora_previsao = as.POSIXct(c("2025-01-01 12:00", "2025-01-01 12:30")),
#'     valor = c(100, 120)
#' )
#'
#' reg <- data.frame(a = c(0.05, 0.06))
#' rownames(reg) <- c("12:00", "12:30")
#'
#' lim <- c(0, 10)
#'
#' df_result <- substitui_por_estimativas(df_ger, df_irrad, reg, lim)
#' print(df_result)
#'
#' @seealso checa_valores_overbound, aplica_cortes_em_geracao

substitui_por_estimativas <- function(df_ger_usi, df_irrad_prev, regressoes, lim_dados) {
    # Adicionar coluna hora:minuto
    df_irrad_prev[, hora_min := format(data_hora_previsao, "%H:%M")]

    # Coeficientes de regressão
    regressoes_dt <- as.data.table(regressoes, keep.rownames = "hora_min")

    # Juntar previsões com os coeficientes por hora:minuto
    df_ger_est <- merge(df_irrad_prev, regressoes_dt, by = "hora_min", all.x = FALSE)
    setnames(df_ger_est, "data_hora_previsao", "data_hora_observacao")

    # Calcular a estimativa: ger_est = a * valor (b = 0 sempre)
    df_ger_est[, ger_est := a * valor]

    # Criar chave de identificação
    df_ger_est[, chave := paste(id_usina, data_hora_observacao)]
    df_ger_usi[, chave := paste(id_usina, data_hora_observacao)]

    # Identificar posições originalmente com NA
    pos_na <- is.na(df_ger_usi$valor)

    # Substituir valores NA por estimativas
    df_ger_usi[pos_na, valor := df_ger_est[.SD, on = "chave", ger_est]]

    # Remover valores fora dos limites
    df_ger_usi[valor > lim_dados[2] | valor < lim_dados[1], valor := NA]

    # Atualizar status = 4 onde houve substituição
    df_ger_usi[pos_na & !is.na(valor), status := 4]

    # Remover chave auxiliar
    df_ger_usi[, chave := NULL]

    return(df_ger_usi)
}


#' Zera Valores em Horarios Fora do Intervalo Valido
#'
#' Substitui por zero os valores de geracao observada em horarios extremos do dia que nao possuem valores validos.
#'
#' @param df_ger_usi data.table contendo os dados de geracao observada. Deve conter as colunas:
#'   \itemize{
#'     \item \code{data_hora_observacao}: POSIXct com a data e hora da observacao.
#'     \item \code{valor}: valor numerico da geracao observada.
#'   }
#'
#' @return O mesmo data.table de entrada, com os valores fora do intervalo valido de horario substituidos por zero.
#'
#' @details
#' A funcao calcula o horario em formato decimal (por exemplo, 6.5 representa 06:30).
#' Em seguida, identifica o menor e o maior horario com pelo menos um valor nao ausente (\code{!is.na(valor)}).
#' Todos os valores fora desse intervalo de horario sao substituidos por zero.
#'
#' Se nenhum valor valido estiver presente, a funcao retorna o data.table original sem alteracoes.
#'
#' @examples
#' library(data.table)
#'
#' df <- data.table(
#'     data_hora_observacao = as.POSIXct(c(
#'         "2025-01-01 00:00", "2025-01-01 06:30", "2025-01-01 07:00",
#'         "2025-01-01 18:00", "2025-01-01 23:30"
#'     )),
#'     valor = c(NA, 10, 12, 11, NA)
#' )
#'
#' df_modificado <- zera_horarios_extremos(df)
#' print(df_modificado)
#'
#' @seealso aplica_cortes_em_geracao, combina_dados

zera_horarios_extremos <- function(df_ger_usi) {
    # Extrair hora:minuto como decimal (ex: 6.5 = 06:30)
    df_ger_usi[, hora_dec := hour(data_hora_observacao) + minute(data_hora_observacao) / 60]

    # Identificar horas que têm pelo menos um valor não NA
    horas_validas <- unique(df_ger_usi[!is.na(valor), hora_dec])

    if (length(horas_validas) == 0) {
        return(df_ger_usi)
    } # Nenhum dado válido

    min_hora <- max(4, c(min(c(horas_validas, 6))))
    max_hora <- min(20, c(max(c(horas_validas, 18))))

    # Substituir por 0 as horas fora do intervalo
    df_ger_usi[hora_dec < min_hora | hora_dec > max_hora, valor := 0]

    # Substituir por NA as horas que o status e NA
    df_ger_usi[is.na(status), valor := NA_real_]


    # Remover coluna auxiliar
    df_ger_usi[, hora_dec := NULL]

    return(df_ger_usi)
}


#' Aplica Cortes em Serie de Geracao
#'
#' Define como NA os valores de geracao observada em datas e usinas onde ha cortes ativos.
#'
#' @param dt_geracao_usina data.table contendo a serie de geracao observada, com colunas obrigatorias: \code{id_usina}, \code{data_hora_observacao}, \code{valor}.
#' @param dt_cortes data.table com informacoes de cortes, contendo colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor},
#'                  onde \code{valor == 1} indica a presenca de corte ativo.
#'
#' @return O mesmo data.table de entrada \code{dt_geracao_usina}, com os valores substituidos por NA nas datas e usinas onde ha cortes.
#'
#' @details
#' A funcao identifica os registros no data.table de cortes em que \code{valor == 1}, o que indica que ha corte ativo naquele instante.
#' Em seguida, esses registros sao usados para sobrescrever a geracao observada com NA na tabela de entrada.
#'
#' @examples
#' library(data.table)
#' dt_geracao <- data.table(
#'     id_usina = c("U1", "U1", "U1", "U2"),
#'     data_hora_observacao = as.POSIXct(c("2025-01-01 00:00", "2025-01-01 00:30", "2025-01-01 01:00", "2025-01-01 00:00")),
#'     valor = c(10, 12, 11, 9)
#' )
#'
#' dt_cortes <- data.table(
#'     id_usina = c("U1", "U2"),
#'     data_hora_observacao = as.POSIXct(c("2025-01-01 00:30", "2025-01-01 00:00")),
#'     valor = c(1, 1)
#' )
#'
#' dt_resultado <- aplica_cortes_em_geracao(dt_geracao, dt_cortes)
#' print(dt_resultado)
#'
#' @seealso combina_dados, organiza_resultados

aplica_cortes_em_geracao <- function(dt_geracao_usina, dt_cortes) {
    # Filtrar apenas onde valor == 1 (cortes ativos)
    dt_cortes_filtrado <- dt_cortes[valor == 1, .(id_usina, data_hora_observacao)]

    # Aplicar NA para todos os id_fonte_observacao em dt_geracao_usina nessas datas
    dt_geracao_usina[dt_cortes_filtrado, on = .(id_usina, data_hora_observacao), valor := NA]

    return(dt_geracao_usina)
}
