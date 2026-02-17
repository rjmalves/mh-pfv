test_that("predict_main completes without error after training", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()

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
    config_predict$output <- temp_output
    config_predict <- parse_config(config_predict, conn)

    expect_no_error(predict_main(config_predict))
})

test_that("predict_main produces valid output files", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()

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
    config_predict$output <- temp_output
    config_predict <- parse_config(config_predict, conn)

    predict_main(config_predict)

    expected_files <- c(
        "melhor_historico_geracao.parquet",
        "melhor_historico_geracao_sem_cortes.parquet"
    )
    output_paths <- file.path(temp_output, expected_files)
    expect_true(all(file.exists(output_paths)))

    expected_cols <- c(
        "id_fonte_observacao", "id_usina",
        "data_hora_observacao", "valor", "status"
    )

    dt_com_cortes <- data.table::setDT(
        arrow::read_parquet(output_paths[1])
    )
    dt_sem_cortes <- data.table::setDT(
        arrow::read_parquet(output_paths[2])
    )

    expect_true(all(expected_cols %in% names(dt_com_cortes)))
    expect_true(all(expected_cols %in% names(dt_sem_cortes)))

    valor_com <- dt_com_cortes$valor
    valor_sem <- dt_sem_cortes$valor
    expect_true(all(is.na(valor_com) | is.finite(valor_com)))
    expect_true(all(is.na(valor_sem) | is.finite(valor_sem)))

    expected_ids <- config_predict$ids_usinas
    expect_true(all(unique(dt_com_cortes$id_usina) %in% expected_ids))
    expect_true(all(unique(dt_sem_cortes$id_usina) %in% expected_ids))

    fonte_com <- dt_com_cortes$id_fonte_observacao[
        !is.na(dt_com_cortes$id_fonte_observacao)
    ]
    fonte_sem <- dt_sem_cortes$id_fonte_observacao[
        !is.na(dt_sem_cortes$id_fonte_observacao)
    ]
    expect_true(all(fonte_com == "Consis"))
    expect_true(all(fonte_sem == "Consis"))
})
