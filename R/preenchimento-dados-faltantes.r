preenche_geracao_unit <- function(dados_usina, geracao_usina, irrad_prev, mhg_prev, cortes, limite_dados) {
    geracao_usina[valor == 999, valor := NA]
    irrad_prev[valor == 999, valor := NA]


    # ajusta modelo de regressao linear
    if (!is.null(cortes)) {
        geracao_usina <- aplica_cortes_em_geracao(
            dt_geracao_usina = copy(geracao_usina),
            dt_cortes = copy(cortes)
        )
    }


    # ajusta modelo de regressao linear
    regressoes <- ajusta_regressao_ger_irrad(
        dty = copy(geracao_usina),
        dtx = copy(irrad_prev),
    )

    # preenche dados faltantes pela estimativa
    geracao_usina_completo <- substitui_por_estimativas(
        df_ger_usi = copy(geracao_usina),
        df_irrad_prev = copy(irrad_prev),
        regressoes = regressoes,
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
        df_ger_usi = resultado_combinado
    )

    return(geracao_usina_completo_final)
}



# AUXILIARES ---------------------------------------------------------------------------------------


ajusta_regressao_ger_irrad <- function(dty, dtx, plotar = TRUE, save_rds = TRUE) {
    dty[valor == 0, valor := NA]
    dtx[valor == 0, valor := NA]

    horas_meia_hora <- seq(5.0, 18.5, by = 0.5)

    angulares <- c() # a (inclinação)
    lineares <- c() # b (sempre zero)
    nomes_linhas <- c()

    for (h in horas_meia_hora) {
        hora_inteira <- floor(h)
        minuto <- ifelse((h - hora_inteira) == 0.5, 30, 0)

        dty_f <- dty[hour(data_hora_observacao) == hora_inteira &
            minute(data_hora_observacao) == minuto]

        dtx_fn <- dtx[hour(data_hora_previsao) == hora_inteira &
            minute(data_hora_previsao) == minuto]

        # Faz o filtro: mantém somente valores em dtx_f com datas e usinas presentes em dty_f
        dtx_f <- dtx_fn[dty_f, on = .(id_usina, data_hora_previsao = data_hora_observacao), nomatch = 0]



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

                # if (plotar) {
                #   dados_plot <- data.frame(irradiacao = x, geracao = y)
                #   p <- ggplot(dados_plot, aes(x = irradiacao, y = geracao)) +
                #     geom_point(alpha = 0.6, color = "gray30") +
                #     geom_abline(intercept = b, slope = a, color = "blue", linewidth = 1.2) +
                #     labs(
                #       title = paste("Regressão linear (forçada) -", hora_txt),
                #       x = "Irradiação",
                #       y = "Geração"
                #     ) +
                #     theme_minimal()
                #   print(p)
                # }
            } else {
                angulares <- c(angulares, 0)
                lineares <- c(lineares, 0)
                hora_txt <- sprintf("%02d:%02d", hora_inteira, minuto)
                nomes_linhas <- c(nomes_linhas, hora_txt)
            }
        }
    }

    reg_par <- data.frame(a = angulares, b = lineares, row.names = nomes_linhas)

    return(reg_par)
}



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

    # Atualizar status = 4 onde houve substituição
    df_ger_usi[pos_na & !is.na(valor), status := 4]

    # Remover chave auxiliar
    df_ger_usi[, chave := NULL]

    # Remover valores fora dos limites
    df_ger_usi[valor > lim_dados[2] | valor < lim_dados[1], valor := NA]

    return(df_ger_usi)
}



zera_horarios_extremos <- function(df_ger_usi) {
    # Extrair hora:minuto como decimal (ex: 6.5 = 06:30)
    df_ger_usi[, hora_dec := hour(data_hora_observacao) + minute(data_hora_observacao) / 60]

    # Identificar horas que têm pelo menos um valor não NA
    horas_validas <- unique(df_ger_usi[!is.na(valor), hora_dec])

    if (length(horas_validas) == 0) {
        return(df_ger_usi)
    } # Nenhum dado válido

    min_hora <- min(horas_validas)
    max_hora <- max(horas_validas)

    # Substituir por 0 as horas fora do intervalo
    df_ger_usi[hora_dec < min_hora | hora_dec > max_hora, valor := 0]

    # Remover coluna auxiliar
    df_ger_usi[, hora_dec := NULL]

    return(df_ger_usi)
}


aplica_cortes_em_geracao <- function(dt_geracao_usina, dt_cortes) {
    # Filtrar apenas onde valor == 1 (cortes ativos)
    dt_cortes_filtrado <- dt_cortes[valor == 1, .(id_usina, data_hora_observacao)]

    # Aplicar NA para todos os id_fonte_observacao em dt_geracao_usina nessas datas
    dt_geracao_usina[dt_cortes_filtrado, on = .(id_usina, data_hora_observacao), valor := NA]

    return(dt_geracao_usina)
}
