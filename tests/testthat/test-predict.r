test_that("get_dataset returns named list with all components", {
    skip_if_not(dir.exists(test_path("data")))

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config <- parse_config(config, conn)

    dataset <- get_dataset(config, conn)

    expect_true(is.list(dataset))
    expected_names <- c(
        "ger_obs", "corte", "irrad_prev", "mhg", "mhg_sem_cortes"
    )
    expect_named(dataset, expected_names)
})

test_that("get_dataset components are data.tables with rows", {
    skip_if_not(dir.exists(test_path("data")))

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config <- parse_config(config, conn)

    dataset <- get_dataset(config, conn)

    for (nm in names(dataset)) {
        expect_true(
            is.data.table(dataset[[nm]]) || is.data.frame(dataset[[nm]])
        )
        expect_gt(nrow(dataset[[nm]]), 0)
    }
})

test_that("processar_usina returns list with com_cortes and sem_cortes", {
    skip_if_not(dir.exists(test_path("data")))

    temp_artifact <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))

    config_train <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train <- parse_config(config_train, conn)

    train_main(config_train)

    config_predict <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict <- parse_config(config_predict, conn)

    dataset <- get_dataset(config_predict, conn)
    dt_usinas <- get_usinas(conn, id_usina = config_predict$ids_usinas)

    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
    dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)

    iu <- config_predict$ids_usinas[1]
    result <- processar_usina(
        iu,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_mhg = dataset$mhg,
        dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
        dt_irrad_prev_filt = dt_irrad_prev_filt,
        dt_corte_obs = dataset$corte,
        fonte = config_predict$ordem_prioridade_fontes,
        fator_tolerancia = config_predict$fator_tolerancia_limite_superior_geracao,
        artifact_dir = temp_artifact
    )

    expect_true(is.list(result))
    expect_named(result, c("com_cortes", "sem_cortes"), ignore.order = TRUE)
    expect_true(is.data.table(result$com_cortes))
    expect_true(is.data.table(result$sem_cortes))
})

test_that("processar_usina output data.tables have rows and expected columns", {
    skip_if_not(dir.exists(test_path("data")))

    temp_artifact <- withr::local_tempdir()
    conn <- conectamock_pfv(test_path("data"))

    config_train <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train <- parse_config(config_train, conn)

    train_main(config_train)

    config_predict <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict <- parse_config(config_predict, conn)

    dataset <- get_dataset(config_predict, conn)
    dt_usinas <- get_usinas(conn, id_usina = config_predict$ids_usinas)

    dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
    dt_irrad_prev_filt <- adicionar_passo_previsao(dt_irrad_prev_filt)

    iu <- config_predict$ids_usinas[1]
    result <- processar_usina(
        iu,
        dt_usinas = dt_usinas,
        dt_ger_obs = dataset$ger_obs,
        dt_mhg = dataset$mhg,
        dt_mhg_sem_cortes = dataset$mhg_sem_cortes,
        dt_irrad_prev_filt = dt_irrad_prev_filt,
        dt_corte_obs = dataset$corte,
        fonte = config_predict$ordem_prioridade_fontes,
        fator_tolerancia = config_predict$fator_tolerancia_limite_superior_geracao,
        artifact_dir = temp_artifact
    )

    expect_gt(nrow(result$com_cortes), 0)
    expect_gt(nrow(result$sem_cortes), 0)
    expect_true("valor" %in% names(result$com_cortes))
    expect_true("valor" %in% names(result$sem_cortes))
})

test_that("organiza_resultados", {
    resultados <- list(
        list(
            com_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 00:00"),
                valor = 10
            ),
            sem_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 00:00"),
                valor = 12
            )
        ),
        list(
            com_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 01:00"),
                valor = 20
            ),
            sem_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 01:00"),
                valor = 22
            )
        )
    )

    v_usinas <- c("U1", "U2")
    resultado <- organiza_resultados(resultados, v_usinas)

    expect_named(resultado, c("com_cortes", "sem_cortes"))

    expect_true(all(c("data_hora_observacao", "valor", "id_usina") %in% names(resultado$com_cortes)))
    expect_true(all(c("data_hora_observacao", "valor", "id_usina") %in% names(resultado$sem_cortes)))

    expect_equal(nrow(resultado$com_cortes), 2)
    expect_equal(nrow(resultado$sem_cortes), 2)
    expect_equal(sort(resultado$com_cortes$id_usina), sort(v_usinas))
    expect_equal(sort(resultado$sem_cortes$id_usina), sort(v_usinas))

    expect_equal(resultado$com_cortes[order(id_usina)]$valor, c(10, 20))
    expect_equal(resultado$sem_cortes[order(id_usina)]$valor, c(12, 22))

    resultado_vazio <- organiza_resultados(list(), character())
    expect_true(is.data.table(resultado_vazio$com_cortes))
    expect_true(is.data.table(resultado_vazio$sem_cortes))
    expect_equal(nrow(resultado_vazio$com_cortes), 0)
    expect_equal(nrow(resultado_vazio$sem_cortes), 0)
})
