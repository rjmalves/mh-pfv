test_that("snapshot_train_model_coefficients", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    train_main(config)

    expected_ids <- config$ids_usinas
    artifact_files <- file.path(
        temp_artifact, paste0(expected_ids, ".rds")
    )

    for (i in seq_along(artifact_files)) {
        artifact <- readRDS(artifact_files[i])

        snapshot_repr <- list(
            id_usina = artifact$id_usina,
            row_names = rownames(artifact$parametros),
            a = round(artifact$parametros$a, 8),
            b = round(artifact$parametros$b, 8)
        )

        expect_snapshot_value(
            snapshot_repr,
            style = "json2",
            tolerance = 1e-6
        )
    }
})

test_that("snapshot_predict_output_summary", {
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

    parquet_path <- file.path(temp_output, "melhor_historico_geracao.parquet")
    dt <- data.table::setDT(arrow::read_parquet(parquet_path))

    expected_ids <- config_predict$ids_usinas

    for (iu in expected_ids) {
        dt_plant <- dt[id_usina == iu]

        summary_list <- list(
            id_usina = iu,
            n_rows = nrow(dt_plant),
            n_na = sum(is.na(dt_plant$valor)),
            mean_valor = round(mean(dt_plant$valor, na.rm = TRUE), 6),
            sd_valor = round(sd(dt_plant$valor, na.rm = TRUE), 6),
            min_valor = round(min(dt_plant$valor, na.rm = TRUE), 6),
            max_valor = round(max(dt_plant$valor, na.rm = TRUE), 6),
            status_counts = as.list(table(dt_plant$status))
        )

        expect_snapshot_value(
            summary_list,
            style = "json2",
            tolerance = 1e-4
        )
    }
})
