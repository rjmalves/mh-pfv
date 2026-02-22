test_that("train_main resume skips completed plants", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config <- parse_config(config, conn)

    plant_ids <- config$ids_usinas
    expect_true(length(plant_ids) >= 2L)

    prov <- create_provenance(config, "train", FALSE)
    prov <- update_plant_status(prov, plant_ids[1], "completed")
    mhpfv:::write_checkpoint(prov, tmp_artifact)

    artifact_before <- gen_model_artifact(id_usina = plant_ids[1])
    saveRDS(artifact_before, file.path(tmp_artifact, paste0(plant_ids[1], ".rds")))

    train_main(config, resume = TRUE)

    artifact_first <- readRDS(file.path(tmp_artifact, paste0(plant_ids[1], ".rds")))
    expect_equal(artifact_first$parametros, artifact_before$parametros)

    artifact_second_path <- file.path(tmp_artifact, paste0(plant_ids[2], ".rds"))
    expect_true(file.exists(artifact_second_path))
    artifact_second <- readRDS(artifact_second_path)
    expect_equal(artifact_second$id_usina, plant_ids[2])
})

test_that("train_main resume with config mismatch runs from scratch", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config <- parse_config(config, conn)

    config_other <- gen_config(
        mode = "train",
        janela = list("2024-01-01", "2024-03-31")
    )
    config_other$input <- test_path("data")
    config_other$artifact <- tmp_artifact
    config_other <- parse_config(config_other, conn)

    plant_ids <- config$ids_usinas
    prov <- create_provenance(config_other, "train", FALSE)
    prov <- update_plant_status(prov, plant_ids[1], "completed")
    mhpfv:::write_checkpoint(prov, tmp_artifact)

    expect_no_error(train_main(config, resume = TRUE))

    for (iu in plant_ids) {
        expect_true(file.exists(file.path(tmp_artifact, paste0(iu, ".rds"))))
    }
})

test_that("train_main cleans up checkpoint after successful run", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config <- parse_config(config, conn)

    train_main(config, resume = TRUE)

    cp_files <- list.files(tmp_artifact, "^checkpoint-.*\\.json$")
    expect_equal(length(cp_files), 0L)

    prov_files <- list.files(tmp_artifact, "^provenance-.*\\.json$")
    expect_equal(length(prov_files), 1L)
})

test_that("train_main without resume runs normally and does not create checkpoint", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config <- parse_config(config, conn)

    expect_no_error(train_main(config, resume = FALSE))

    cp_files <- list.files(tmp_artifact, "^checkpoint-.*\\.json$")
    expect_equal(length(cp_files), 0L)
})

test_that("train_main resume with no existing checkpoint runs from scratch", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config <- parse_config(config, conn)

    expect_no_error(train_main(config, resume = TRUE))

    for (iu in config$ids_usinas) {
        expect_true(file.exists(file.path(tmp_artifact, paste0(iu, ".rds"))))
    }
})

test_that("predict_main resume combines old and new results", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()
    tmp_output <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config_train <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_train$input <- test_path("data")
    config_train$artifact <- tmp_artifact
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    config <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config$output <- tmp_output
    config <- parse_config(config, conn)

    plant_ids <- config$ids_usinas
    expect_true(length(plant_ids) >= 2L)

    config_seq <- config
    predict_main(config_seq)

    pr_file <- file.path(tmp_output, paste0("plant-result-", plant_ids[1], ".rds"))
    dt_full <- data.table::setDT(
        arrow::read_parquet(file.path(tmp_output, "melhor_historico_geracao.parquet"))
    )
    n_rows_full <- nrow(dt_full)

    saved_result <- list(
        com_cortes = dt_full[id_usina == plant_ids[1]],
        sem_cortes = dt_full[id_usina == plant_ids[1]]
    )
    mhpfv:::write_plant_result(saved_result, plant_ids[1], tmp_output)

    prov <- create_provenance(config, "predict", FALSE)
    prov <- update_plant_status(prov, plant_ids[1], "completed")
    mhpfv:::write_checkpoint(prov, tmp_output)

    tmp_output2 <- withr::local_tempdir()
    config$output <- tmp_output2

    file.copy(
        file.path(tmp_output, paste0("plant-result-", plant_ids[1], ".rds")),
        file.path(tmp_output2, paste0("plant-result-", plant_ids[1], ".rds"))
    )
    file.copy(
        list.files(tmp_output, "^checkpoint-.*\\.json$", full.names = TRUE),
        file.path(tmp_output2, basename(
            list.files(tmp_output, "^checkpoint-.*\\.json$", full.names = TRUE)
        ))
    )

    expect_no_error(predict_main(config, resume = TRUE))

    result_files <- c(
        "melhor_historico_geracao.parquet",
        "melhor_historico_geracao_sem_cortes.parquet"
    )
    for (f in result_files) {
        expect_true(file.exists(file.path(tmp_output2, f)))
    }

    dt_resume <- data.table::setDT(
        arrow::read_parquet(file.path(tmp_output2, "melhor_historico_geracao.parquet"))
    )
    ids_in_output <- unique(dt_resume$id_usina)
    expect_true(all(plant_ids %in% ids_in_output))
})

test_that("predict_main cleans up checkpoint after successful resume run", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()
    tmp_output <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config_train <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_train$input <- test_path("data")
    config_train$artifact <- tmp_artifact
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    config <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config$output <- tmp_output
    config <- parse_config(config, conn)

    predict_main(config, resume = TRUE)

    cp_files <- list.files(tmp_output, "^checkpoint-.*\\.json$")
    expect_equal(length(cp_files), 0L)

    pr_files <- list.files(tmp_output, "^plant-result-.*\\.rds$")
    expect_equal(length(pr_files), 0L)

    prov_files <- list.files(tmp_output, "^provenance-.*\\.json$")
    expect_equal(length(prov_files), 1L)
})

test_that("predict_main resume with missing plant result reprocesses that plant", {
    skip_if_not(dir.exists(test_path("data")))
    tmp_artifact <- withr::local_tempdir()
    tmp_output <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config_train <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config_train$input <- test_path("data")
    config_train$artifact <- tmp_artifact
    config_train <- parse_config(config_train, conn)
    train_main(config_train)

    config <- gen_config(
        mode = "predict",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- tmp_artifact
    config$output <- tmp_output
    config <- parse_config(config, conn)

    plant_ids <- config$ids_usinas
    prov <- create_provenance(config, "predict", FALSE)
    prov <- update_plant_status(prov, plant_ids[1], "completed")
    mhpfv:::write_checkpoint(prov, tmp_output)

    expect_no_error(predict_main(config, resume = TRUE))

    dt_result <- data.table::setDT(
        arrow::read_parquet(file.path(tmp_output, "melhor_historico_geracao.parquet"))
    )
    expect_true(all(plant_ids %in% unique(dt_result$id_usina)))
})
