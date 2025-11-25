#' Preenche Serie de Geracao para com Estimativas
#'
#' Realiza o preenchimento de valores ausentes na geracao observada de uma usina, utilizando irradiacao prevista corrigida por regressao linear.
#'
#' @param geracao_usina data.table com os dados de geracao observada da usina. Deve conter colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor}.
#' @param irrad_prev data.table com previsao de irradiancia. Deve conter colunas \code{id_usina}, \code{data_hora_previsao} e \code{valor}.
#' @param mhg_prev data.table com melhores historicos de geracao anteriores. Deve conter colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor}.
#' @param cortes data.table com registros de cortes (opcional). Deve conter colunas \code{id_usina}, \code{data_hora_observacao} e \code{valor} (1 para corte).
#' @param limite_dados Vetor numerico de comprimento 2 com os limites inferior e superior permitidos para valores de geracao.
#' @param model Lista contendo os modelos de regressao linear por horario.
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
#' @seealso ajusta_regressao_ger_irrad, substitui_por_estimativas, aplica_cortes_em_geracao, combina_dados_tempo, zera_horarios_extremos
#'
preenche_geracao_unit <- function(geracao_usina, irrad_prev, mhg_prev, cortes, limite_dados, model) {
    geracao_usina[valor == 999, valor := NA]
    irrad_prev[valor == 999, valor := NA]
    geracao_usina_bruta <- copy(geracao_usina)

    if (!is.null(cortes)) {
        geracao_usina <- aplica_cortes_em_geracao(
            dt_geracao_usina = copy(geracao_usina),
            dt_cortes = copy(cortes)
        )
    }

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
#' @seealso checa_valores_overbound, aplica_cortes_em_geracao
#'
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
#' @seealso aplica_cortes_em_geracao, combina_dados
#'
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
#' @seealso combina_dados, organiza_resultados
#'
aplica_cortes_em_geracao <- function(dt_geracao_usina, dt_cortes) {
    # Filtrar apenas onde valor == 1 (cortes ativos)
    dt_cortes_filtrado <- dt_cortes[valor == 1, .(id_usina, data_hora_observacao)]

    # Aplicar NA para todos os id_fonte_observacao em dt_geracao_usina nessas datas
    dt_geracao_usina[dt_cortes_filtrado, on = .(id_usina, data_hora_observacao), valor := NA]

    return(dt_geracao_usina)
}
