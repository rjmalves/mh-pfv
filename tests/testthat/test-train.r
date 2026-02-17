test_that("ajustar_usina returns list with id_usina and parametros", {
    skip_if_not(dir.exists(test_path("data")))

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config <- parse_config(config, conn)

    dataset <- get_dataset(config, conn)
    dt_usinas <- get_usinas(conn, id_usina = config$ids_usinas)

    iu <- config$ids_usinas[1]
    result <- ajustar_usina(
        iu,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_irrad_prev = dataset$irrad_prev,
        dt_corte_obs = dataset$corte,
        fonte = config$ordem_prioridade_fontes,
        fator_tolerancia = config$fator_tolerancia_limite_superior_geracao
    )

    expect_true(is.list(result))
    expect_named(result, c("id_usina", "parametros"), ignore.order = TRUE)
    expect_true(is.character(result$id_usina))
    expect_equal(result$id_usina, iu)
    expect_true(is.data.frame(result$parametros))
})

test_that("ajustar_usina parametros has expected structure", {
    skip_if_not(dir.exists(test_path("data")))

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config <- parse_config(config, conn)

    dataset <- get_dataset(config, conn)
    dt_usinas <- get_usinas(conn, id_usina = config$ids_usinas)

    iu <- config$ids_usinas[1]
    result <- ajustar_usina(
        iu,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_irrad_prev = dataset$irrad_prev,
        dt_corte_obs = dataset$corte,
        fonte = config$ordem_prioridade_fontes,
        fator_tolerancia = config$fator_tolerancia_limite_superior_geracao
    )

    params <- result$parametros
    expect_true(all(c("a", "b") %in% names(params)))

    non_na_b <- params$b[!is.na(params$b)]
    expect_true(all(non_na_b == 0))

    non_na_a <- params$a[!is.na(params$a)]
    expect_true(all(is.numeric(non_na_a)))
})

test_that("ajusta_regressao_ger_irrad", {
    horarios <- seq(from = as.POSIXct("2025-01-01 06:00"), by = "1 day", length.out = 10)

    dtx_base <- data.table(
        id_usina = "U1",
        data_hora_previsao = horarios,
        valor = seq(10, 100, by = 10)
    )

    dty_base <- data.table(
        id_usina = "U1",
        data_hora_observacao = horarios,
        valor = seq(2, 20, by = 2)
    )

    resultado <- ajusta_regressao_ger_irrad(copy(dty_base), copy(dtx_base), copy(dty_base))
    expect_equal(rownames(resultado), "06:00")
    expect_gt(resultado["06:00", "a"], 0)
    expect_equal(resultado["06:00", "b"], 0)

    # fewer than 6 valid pairs: no regression fit
    dty_poucos <- dty_base[1:5]
    dtx_poucos <- dtx_base[1:5]
    resultado_poucos <- ajusta_regressao_ger_irrad(copy(dty_poucos), copy(dtx_poucos), copy(dty_poucos))
    expect_equal(nrow(resultado_poucos), 0)

    # zeros are treated as NA
    dty_zero <- copy(dty_base)
    dtx_zero <- copy(dtx_base)
    dty_zero[1:3, valor := 0]
    dtx_zero[1:3, valor := 0]
    resultado_zero <- ajusta_regressao_ger_irrad(copy(dty_zero), copy(dtx_zero), copy(dty_zero))
    expect_equal(rownames(resultado_zero), "06:00")

    # all NA yields NA coefficient
    dty_na <- copy(dty_base)
    dtx_na <- copy(dtx_base)
    dty_na[, valor := NA]
    dtx_na[, valor := NA]
    resultado_na <- ajusta_regressao_ger_irrad(copy(dty_na), copy(dtx_na), copy(dty_na))
    expect_equal(resultado_na["06:00", "a"], NA)

    # half-hour timestamps work correctly
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
