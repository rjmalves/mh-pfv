test_that("preenche_geracao_unit", {
    # Dados base com multiplos dias para horario fixo (06:00)
    dias <- seq(from = as.Date("2025-01-01"), by = "1 day", length.out = 10)
    horarios <- as.POSIXct(paste(dias, "06:00:00"))

    # Teste 1: Preenchimento de NAs com estimativas quando regressao esta disponivel
    geracao_usina <- data.table(
        id_usina = "U1",
        id_fonte_observacao = "PI",
        data_hora_observacao = horarios,
        valor = c(NA, 2, 4, 6, 8, 10, 12, 14, 16, 18),
        status = c(NA, rep(1, 9))
    )

    irrad_prev <- data.table(
        id_usina = "U1",
        data_hora_previsao = horarios,
        valor = seq(10, 100, by = 10)
    )

    mhg_prev <- data.table(
        id_usina = "U1",
        id_fonte_observacao = "PI",
        data_hora_observacao = horarios,
        valor = rep(1, 10),
        status = c(NA, rep(1, 9))
    )

    cortes <- NULL
    limite_dados <- c(0, 25)

    resultado <- preenche_geracao_unit(
        geracao_usina = copy(geracao_usina),
        irrad_prev = copy(irrad_prev),
        mhg_prev = copy(mhg_prev),
        cortes = cortes,
        limite_dados = limite_dados
    )

    expect_true(is.data.table(resultado))
    expect_true("valor" %in% names(resultado))

    # Teste 2: Valores preenchidos nao devem ultrapassar os limites
    expect_true(all(na.omit(resultado$valor) >= 0 & na.omit(resultado$valor) <= 25))

    # Teste 3: Valores com 999 devem ser tratados como NA
    geracao_usina_999 <- copy(geracao_usina)
    geracao_usina_999[1, valor := 999]
    irrad_prev_999 <- copy(irrad_prev)
    irrad_prev_999[1, valor := 999]

    resultado_999 <- preenche_geracao_unit(
        geracao_usina = geracao_usina_999,
        irrad_prev = irrad_prev_999,
        mhg_prev = mhg_prev,
        cortes = cortes,
        limite_dados = limite_dados
    )

    expect_false(any(na.omit(resultado_999$valor) == 999))

    # Teste 4: Quando todos os valores ja estao preenchidos, nenhuma estimativa deve ser aplicada
    geracao_completa <- copy(geracao_usina)
    geracao_completa[is.na(valor), `:=`(status = 1, valor = 20)]
    resultado_completo <- preenche_geracao_unit(
        geracao_usina = geracao_completa,
        irrad_prev = irrad_prev,
        mhg_prev = mhg_prev,
        cortes = NULL,
        limite_dados = limite_dados
    )
    resultado_06h <- resultado_completo[format(data_hora_observacao, "%H:%M:%S") == "06:00:00"]

    expect_equal(resultado_06h$valor, geracao_completa$valor)

    # Teste 5: Quando cortes sao aplicados, valores devem virar NA e depois estimados
    cortes_dt <- data.table(
        id_usina = "U1",
        data_hora_observacao = horarios[1:3],
        valor = c(1, 1, 1)
    )

    resultado_cortes <- preenche_geracao_unit(
        geracao_usina = copy(geracao_usina),
        irrad_prev = irrad_prev,
        mhg_prev = mhg_prev,
        cortes = cortes_dt,
        limite_dados = limite_dados
    )
    resultado_06h <- resultado_cortes[format(data_hora_observacao, "%H:%M:%S") == "06:00:00"]

    expect_false(any(resultado_06h$status[1:3] != 4))

    # Teste 6: Se todos os dados forem NA apos cortes e limite, resultado final deve conter NA
    geracao_na <- copy(geracao_usina)
    geracao_na[, valor := NA]
    irrad_prev_alta <- copy(irrad_prev)
    irrad_prev_alta[, valor := 1e6] # estimativa vai ultrapassar o limite
    mhg_prev$valor <- NA_real_
    resultado_limite <- preenche_geracao_unit(
        geracao_usina = geracao_na,
        irrad_prev = irrad_prev_alta,
        mhg_prev = mhg_prev,
        cortes = NULL,
        limite_dados = c(0, 20)
    )
    resultado_06h <- resultado_limite[format(data_hora_observacao, "%H:%M:%S") == "06:00:00"]

    expect_true(all(is.na(resultado_06h$valor)))
})



test_that("ajusta_regressao_ger_irrad", {
    # Gera dados para multiplos dias, sempre no mesmo horario
    horarios <- seq(from = as.POSIXct("2025-01-01 06:00"), by = "1 day", length.out = 10)

    # Previsao (dtx): irradiancia
    dtx_base <- data.table(
        id_usina = "U1",
        data_hora_previsao = horarios,
        valor = seq(10, 100, by = 10) # irradiancia crescente
    )

    # Observado (dty): geracao
    dty_base <- data.table(
        id_usina = "U1",
        data_hora_observacao = horarios,
        valor = seq(2, 20, by = 2) # geracao proporcional (ex: 0.2 * irradiancia)
    )

    # Teste 1: Ajusta regressao corretamente com multiplos dias no mesmo horario
    resultado <- ajusta_regressao_ger_irrad(copy(dty_base), copy(dtx_base))
    expect_equal(rownames(resultado), "06:00")
    expect_gt(resultado["06:00", "a"], 0)
    expect_equal(resultado["06:00", "b"], 0)

    # Teste 2: Se menos de 6 pares validos, nao ajusta regressao
    dty_poucos <- dty_base[1:5]
    dtx_poucos <- dtx_base[1:5]
    resultado_poucos <- ajusta_regressao_ger_irrad(copy(dty_poucos), copy(dtx_poucos))
    expect_equal(nrow(resultado_poucos), 0)

    # Teste 3: Zeros devem ser tratados como NA
    dty_zero <- copy(dty_base)
    dtx_zero <- copy(dtx_base)
    dty_zero[1:3, valor := 0]
    dtx_zero[1:3, valor := 0]
    resultado_zero <- ajusta_regressao_ger_irrad(copy(dty_zero), copy(dtx_zero))
    expect_equal(rownames(resultado_zero), "06:00")
    expect_gt(resultado_zero["06:00", "a"], 0) # ainda há 7 pares validos

    # Teste 4: Se todos os valores forem NA, nao ajusta regressao e retorna 0
    dty_na <- copy(dty_base)
    dtx_na <- copy(dtx_base)
    dty_na[, valor := NA]
    dtx_na[, valor := NA]
    resultado_na <- ajusta_regressao_ger_irrad(copy(dty_na), copy(dtx_na))
    expect_equal(resultado_na["06:00", "a"], NA)

    # Teste 5: Funciona tambem para horario com minuto (ex: 06:30)
    horarios_0630 <- seq(from = as.POSIXct("2025-01-01 06:30"), by = "1 day", length.out = 10)
    dtx_0630 <- data.table(
        id_usina = "U1",
        data_hora_previsao = horarios_0630,
        valor = seq(10, 100, by = 10)
    )
    dty_0630 <- data.table(
        id_usina = "U1",
        data_hora_observacao = horarios_0630,
        valor = seq(3, 30, by = 3)
    )
    resultado_0630 <- ajusta_regressao_ger_irrad(copy(dty_0630), copy(dtx_0630))
    expect_equal(rownames(resultado_0630), "06:30")
    expect_gt(resultado_0630["06:30", "a"], 0)
})



test_that("substitui_por_estimativas", {
    # Dados de geracao com NAs a serem substituidos
    df_ger_usi <- data.table(
        id_usina = c("U1", "U1", "U2"),
        data_hora_observacao = as.POSIXct(c("2025-01-01 06:00", "2025-01-01 07:00", "2025-01-01 08:00")),
        valor = c(NA, 10, NA),
        status = c(NA, 2, NA)
    )

    # Previsao de irradiancia
    df_irrad_prev <- data.table(
        id_usina = c("U1", "U1", "U2"),
        data_hora_previsao = as.POSIXct(c("2025-01-01 06:00", "2025-01-01 07:00", "2025-01-01 08:00")),
        valor = c(50, 60, 70)
    )

    # Coeficientes de regressao (b = 0, entao so "a" importa)
    regressoes <- data.frame(
        a = c(0.2, 0.3, 0.4),
        row.names = c("06:00", "07:00", "08:00")
    )

    lim_dados <- c(0, 20)

    # Teste 1: Substituicao correta de valores NA usando estimativas
    resultado <- substitui_por_estimativas(copy(df_ger_usi), df_irrad_prev, regressoes, lim_dados)
    expect_equal(resultado$valor, c(10, 10, NA)) # 0.2*50=10, valor mantido, 0.4*70=28 -> NA por limite
    expect_equal(resultado$status, c(4, 2, NA)) # Apenas o primeiro substituido e dentro do limite

    # Teste 2: Nenhum valor NA na geracao, nada deve mudar
    df2 <- data.table(
        id_usina = c("U1", "U2"),
        data_hora_observacao = as.POSIXct(c("2025-01-01 06:00", "2025-01-01 08:00")),
        valor = c(15, 12),
        status = c(1, 2)
    )
    resultado2 <- substitui_por_estimativas(copy(df2), df_irrad_prev, regressoes, lim_dados)
    expect_equal(resultado2$valor, c(15, 12))
    expect_equal(resultado2$status, c(1, 2))

    # Teste 3: Valor estimado fora dos limites deve ser convertido em NA
    df3 <- data.table(
        id_usina = c("U2"),
        data_hora_observacao = as.POSIXct("2025-01-01 08:00"),
        valor = NA,
        status = NA
    )
    resultado3 <- substitui_por_estimativas(copy(df3), df_irrad_prev, regressoes, lim_dados)
    expect_true(is.na(resultado3$valor))
    expect_true(is.na(resultado3$status))

    # Teste 4: Nenhum valor estimado porque hora nao esta nas regressoes
    df_irrad_invalida <- data.table(
        id_usina = c("U1"),
        data_hora_previsao = as.POSIXct("2025-01-01 09:00"),
        valor = 80
    )
    df4 <- data.table(
        id_usina = c("U1"),
        data_hora_observacao = as.POSIXct("2025-01-01 09:00"),
        valor = NA,
        status = NA
    )
    resultado4 <- substitui_por_estimativas(copy(df4), df_irrad_invalida, regressoes, lim_dados)
    expect_true(is.na(resultado4$valor))
    expect_true(is.na(resultado4$status))

    # Teste 5: Todos os valores estimados dentro do limite
    df5 <- data.table(
        id_usina = c("U1"),
        data_hora_observacao = as.POSIXct("2025-01-01 06:00"),
        valor = NA,
        status = NA
    )
    resultado5 <- substitui_por_estimativas(copy(df5), df_irrad_prev, regressoes, c(0, 100))
    expect_equal(resultado5$valor, 10)
    expect_equal(resultado5$status, 4)
})



test_that("zera_horarios_extremos", {
    # Teste 1: Zera horarios antes e depois do intervalo com valor nao NA
    df <- data.table(
        data_hora_observacao = as.POSIXct(c(
            "2025-01-01 04:00", "2025-01-01 06:00", "2025-01-01 07:00", "2025-01-01 08:00", "2025-01-01 10:00"
        )),
        valor = c(NA, 10, 15, 20, 10),
        status = rep(1, 5)
    )

    resultado <- zera_horarios_extremos(copy(df))
    expect_equal(resultado$valor, c(0, 10, 15, 20, 10))

    # Teste 2: Nenhum valor nao NA, deve retornar igual
    df2 <- data.table(
        data_hora_observacao = as.POSIXct(c("2025-01-01 01:00", "2025-01-01 02:00")),
        valor = c(NA, NA)
    )

    resultado2 <- zera_horarios_extremos(copy(df2))
    expect_equal(resultado2$valor, c(NA, NA))

    # Teste 3: Todos os horarios com valor nao NA, nada deve ser zerado
    df3 <- data.table(
        data_hora_observacao = as.POSIXct(c("2025-01-01 05:00", "2025-01-01 06:00", "2025-01-01 07:00")),
        valor = c(5, 6, 7),
        status = rep(1, 3)
    )

    resultado3 <- zera_horarios_extremos(copy(df3))
    expect_equal(resultado3$valor, df3$valor)

    # Teste 4: Valores nao NA somente no primeiro e ultimo horario
    df4 <- data.table(
        data_hora_observacao = as.POSIXct(c(
            "2025-01-01 03:00",
            "2025-01-01 04:00", "2025-01-01 05:00", "2025-01-01 06:00"
        )),
        valor = c(1, NA, 2, 4),
        status = rep(1, 4)
    )

    resultado4 <- zera_horarios_extremos(copy(df4))
    expect_equal(resultado4$valor, c(0, NA, 2, 4))
})


test_that("aplica_cortes_em_geracao", {
    # Teste 1: Aplica corte simples em U1 no horario 00:00
    dt_geracao <- data.table(
        id_usina = c("U1", "U1", "U2", "U2"),
        data_hora_observacao = as.POSIXct(c(
            "2025-01-01 00:00", "2025-01-01 01:00",
            "2025-01-01 00:00", "2025-01-01 01:00"
        )),
        id_fonte_observacao = c("A", "A", "B", "B"),
        valor = c(10, 20, 30, 40)
    )

    dt_cortes <- data.table(
        id_usina = c("U1", "U2"),
        data_hora_observacao = as.POSIXct(c("2025-01-01 00:00", "2025-01-01 01:00")),
        valor = c(1, 0) # apenas o primeiro corte esta ativo
    )

    resultado <- aplica_cortes_em_geracao(copy(dt_geracao), dt_cortes)
    expect_equal(resultado$valor, c(NA, 20, 30, 40))

    # Teste 2: Verifica se colunas restantes permanecem inalteradas
    expect_equal(resultado$id_usina, dt_geracao$id_usina)
    expect_equal(resultado$id_fonte_observacao, dt_geracao$id_fonte_observacao)

    # Teste 3: Nenhum corte aplicado quando dt_cortes esta vazio
    resultado_vazio <- aplica_cortes_em_geracao(copy(dt_geracao), dt_cortes[0])
    expect_equal(resultado_vazio$valor, dt_geracao$valor)

    # Teste 4: dt_geracao vazio deve retornar tabela vazia com mesmas colunas
    resultado_geracao_vazio <- aplica_cortes_em_geracao(dt_geracao[0], dt_cortes)
    expect_equal(nrow(resultado_geracao_vazio), 0)
    expect_equal(names(resultado_geracao_vazio), names(dt_geracao))

    # Teste 5: Corte para usina e horario nao existente na geracao nao deve afetar nada
    dt_cortes_extra <- data.table(
        id_usina = "U3",
        data_hora_observacao = as.POSIXct("2025-01-01 02:00"),
        valor = 1
    )
    resultado_extra <- aplica_cortes_em_geracao(copy(dt_geracao), dt_cortes_extra)
    expect_equal(resultado_extra$valor, dt_geracao$valor)
})
