test_that("predict_main completes without error after training", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
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
    skip_if_no_zstd()
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

test_that("predict_main accepts custom strategy", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
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

    strategy <- linear_regression_strategy()
    expect_no_error(predict_main(config_predict, strategy = strategy))
})

test_that("predict_main handles legacy artifacts without metadata", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()
    temp_output <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))

    config_predict <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_predict$input <- test_path("data")
    config_predict$artifact <- temp_artifact
    config_predict$output <- temp_output
    config_predict <- parse_config(config_predict, conn)

    plant_ids <- config_predict$ids_usinas
    for (iu in plant_ids) {
        artifact <- gen_model_artifact_legacy(id_usina = iu)
        saveRDS(artifact, file.path(temp_artifact, paste0(iu, ".rds")))
    }

    expect_no_error(predict_main(config_predict))

    expected_files <- c(
        "melhor_historico_geracao.parquet",
        "melhor_historico_geracao_sem_cortes.parquet"
    )
    output_paths <- file.path(temp_output, expected_files)
    expect_true(all(file.exists(output_paths)))
})

test_that("predict_main parallel produces identical output to sequential", {
    skip_if(
        !is.null(pkgload::dev_meta("mhpfv")),
        "mhpfv loaded via devtools/pkgload (multisession workers need installed package)"
    )
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()

    temp_artifact <- withr::local_tempdir()
    temp_output_seq <- withr::local_tempdir()
    temp_output_par <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config_train <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_train$input <- test_path("data")
    config_train$artifact <- temp_artifact
    config_train <- parse_config(config_train, conn)

    train_main(config_train)

    config_seq <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_seq$input <- test_path("data")
    config_seq$artifact <- temp_artifact
    config_seq$output <- temp_output_seq
    config_seq <- parse_config(config_seq, conn)

    predict_main(config_seq, parallel = FALSE)

    config_par <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_par$input <- test_path("data")
    config_par$artifact <- temp_artifact
    config_par$output <- temp_output_par
    config_par <- parse_config(config_par, conn)

    predict_main(config_par, parallel = TRUE)

    files <- c(
        "melhor_historico_geracao.parquet",
        "melhor_historico_geracao_sem_cortes.parquet"
    )

    for (f in files) {
        dt_seq <- data.table::setDT(
            arrow::read_parquet(file.path(temp_output_seq, f))
        )
        dt_par <- data.table::setDT(
            arrow::read_parquet(file.path(temp_output_par, f))
        )

        data.table::setorderv(dt_seq, c("id_usina", "data_hora_observacao"))
        data.table::setorderv(dt_par, c("id_usina", "data_hora_observacao"))

        expect_equal(nrow(dt_seq), nrow(dt_par))
        expect_equal(names(dt_seq), names(dt_par))
        expect_equal(dt_seq$id_usina, dt_par$id_usina)
        expect_equal(dt_seq$data_hora_observacao, dt_par$data_hora_observacao)
        expect_equal(dt_seq$valor, dt_par$valor, tolerance = 1e-10)
    }
})

test_that("predict_main writes valid provenance JSON", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
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

    prov_files <- list.files(
        temp_output, "^provenance-.*\\.json$", full.names = TRUE
    )
    expect_equal(length(prov_files), 1L)

    parsed <- jsonlite::fromJSON(prov_files[1])
    expect_equal(parsed$status, "completed")
    expect_equal(parsed$n_plants, 2L)
    expect_equal(parsed$mode, "predict")
})

test_that("predict_main writes valid metrics JSON", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
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

    metrics_files <- list.files(
        temp_output, pattern = "^metrics-.*\\.json$", full.names = TRUE
    )
    expect_equal(length(metrics_files), 1L)

    parsed <- jsonlite::fromJSON(metrics_files[1])
    plants <- parsed$plants

    for (plant_name in names(plants)) {
        plant <- plants[[plant_name]]
        expect_true(is.numeric(plant$duration_seconds))
        expect_true(!is.null(plant$data_volume))
        expect_true(!is.null(plant$data_volume$n_rows))
        expect_true(!is.null(plant$data_volume$n_na))
        expect_true(!is.null(plant$data_volume$na_rate))
    }
})
