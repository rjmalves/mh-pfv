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
    resultado <- ajusta_regressao_ger_irrad(copy(dty_base), copy(dtx_base), copy(dty_base))
    expect_equal(rownames(resultado), "06:00")
    expect_gt(resultado["06:00", "a"], 0)
    expect_equal(resultado["06:00", "b"], 0)

    # Teste 2: Se menos de 6 pares validos, nao ajusta regressao
    dty_poucos <- dty_base[1:5]
    dtx_poucos <- dtx_base[1:5]
    resultado_poucos <- ajusta_regressao_ger_irrad(copy(dty_poucos), copy(dtx_poucos), copy(dty_poucos))
    expect_equal(nrow(resultado_poucos), 0)

    # Teste 3: Zeros devem ser tratados como NA
    dty_zero <- copy(dty_base)
    dtx_zero <- copy(dtx_base)
    dty_zero[1:3, valor := 0]
    dtx_zero[1:3, valor := 0]
    resultado_zero <- ajusta_regressao_ger_irrad(copy(dty_zero), copy(dtx_zero), copy(dty_zero))
    expect_equal(rownames(resultado_zero), "06:00")

    # Teste 4: Se todos os valores forem NA, nao ajusta regressao e retorna 0
    dty_na <- copy(dty_base)
    dtx_na <- copy(dtx_base)
    dty_na[, valor := NA]
    dtx_na[, valor := NA]
    resultado_na <- ajusta_regressao_ger_irrad(copy(dty_na), copy(dtx_na), copy(dty_na))
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
    resultado_0630 <- ajusta_regressao_ger_irrad(copy(dty_0630), copy(dtx_0630), copy(dty_0630))
    expect_equal(rownames(resultado_0630), "06:30")
    expect_gt(resultado_0630["06:30", "a"], 0)
})
