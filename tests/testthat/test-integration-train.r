test_that("train_main completes without error", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- normalizePath(test_path("data"))
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    expect_no_error(train_main(config))
})

test_that("train_main accepts strategy as string", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- normalizePath(test_path("data"))
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    expect_no_error(train_main(config, strategy = "linear_regression"))
})

test_that("train_main produces valid model artifacts", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- normalizePath(test_path("data"))
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    train_main(config)

    expected_ids <- config$ids_usinas
    artifact_files <- file.path(
        temp_artifact, paste0(expected_ids, ".rds")
    )

    expect_true(all(file.exists(artifact_files)))
    expect_equal(length(artifact_files), length(expected_ids))

    hhmm_pattern <- "^(0[5-9]|1[0-8]):[0-3]0$"

    for (i in seq_along(artifact_files)) {
        artifact <- readRDS(artifact_files[i])

        expect_true(is.list(artifact))
        expect_true(all(c("id_usina", "model") %in% names(artifact)))

        expect_true(is.character(artifact$id_usina))
        expect_equal(artifact$id_usina, expected_ids[i])

        expect_true(inherits(artifact$model, "linear_regression_model"))
        params <- artifact$model$parametros
        expect_true(is.data.frame(params))
        expect_true(all(c("a", "b") %in% names(params)))

        rnames <- rownames(params)
        expect_true(all(grepl(hhmm_pattern, rnames)))

        rnames_as_hours <- as.numeric(
            sub("^(\\d+):(\\d+)$", "\\1", rnames)
        ) + as.numeric(
            sub("^(\\d+):(\\d+)$", "\\2", rnames)
        ) / 60
        expect_true(all(rnames_as_hours >= 5.0))
        expect_true(all(rnames_as_hours <= 18.5))

        non_na_b <- params$b[!is.na(params$b)]
        expect_true(all(non_na_b == 0))

        non_na_a <- params$a[!is.na(params$a)]
        expect_true(all(is.finite(non_na_a)))
        expect_true(all(is.numeric(non_na_a)))
    }
})

test_that("train_main writes valid provenance JSON", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- normalizePath(test_path("data"))
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    train_main(config)

    prov_files <- list.files(
        temp_artifact, "^provenance-.*\\.json$", full.names = TRUE
    )
    expect_equal(length(prov_files), 1L)

    parsed <- jsonlite::fromJSON(prov_files[1])
    expect_equal(parsed$status, "completed")
    expect_equal(parsed$n_plants, 2L)
    expect_equal(parsed$mode, "train")
})

test_that("train_main writes valid metrics JSON", {
    skip_if_not(dir.exists(test_path("data")))
    skip_if_no_zstd()
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- normalizePath(test_path("data"))
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    train_main(config)

    metrics_files <- list.files(
        temp_artifact, pattern = "^metrics-.*\\.json$", full.names = TRUE
    )
    expect_equal(length(metrics_files), 1L)

    parsed <- jsonlite::fromJSON(metrics_files[1])
    plants <- parsed$plants

    for (plant_name in names(plants)) {
        plant <- plants[[plant_name]]
        expect_true(is.numeric(plant$duration_seconds))
        expect_true(!is.null(plant$model_quality))
        expect_true(!is.null(plant$model_quality$n_slots))
        expect_true(!is.null(plant$model_quality$n_valid_slots))
    }
})

test_that("train_main partial failure: 1 of 3 plants fails", {
    temp_artifact <- withr::local_tempdir()
    config <- gen_config(
        mode = "train",
        ids_usinas = c("USI1", "USI_FAIL", "USI3"),
        janela = list("2025-07-01", "2025-09-30")
    )
    config$artifact <- temp_artifact
    config$input <- temp_artifact

    mockery::stub(train_main, "conectamock_pfv", function(...) NULL)
    mockery::stub(train_main, "get_usinas",
        function(...) gen_usinas(ids = c("USI1", "USI_FAIL", "USI3")))
    mockery::stub(train_main, "get_dataset", function(...) {
        list(
            ger_obs = data.table::data.table(),
            corte = data.table::data.table(),
            irrad_prev = data.table::data.table()
        )
    })
    mockery::stub(train_main, "associa_nwp_usina",
        function(...) data.table::data.table())
    mockery::stub(train_main, "adicionar_passo_previsao",
        function(x, ...) x)
    mockery::stub(train_main, "ajustar_usina", function(iu, ...) {
        if (iu == "USI_FAIL") stop("simulated failure")
        gen_model_artifact(id_usina = iu)
    })
    mockery::stub(train_main, "write_model_artifact",
        function(...) invisible(NULL))

    expect_no_error(train_main(config))

    prov_files <- list.files(temp_artifact, "^provenance-.*\\.json$",
        full.names = TRUE)
    expect_equal(length(prov_files), 1L)
    parsed <- jsonlite::fromJSON(prov_files[1], simplifyVector = FALSE)

    expect_equal(parsed$plant_status$USI1, "completed")
    expect_equal(parsed$plant_status$USI_FAIL, "failed")
    expect_equal(parsed$plant_status$USI3, "completed")
    expect_equal(parsed$status, "failed")

    report_files <- list.files(temp_artifact, "^health-.*\\.json$",
        full.names = TRUE)
    expect_equal(length(report_files), 1L)
    report <- jsonlite::fromJSON(report_files[1], simplifyVector = FALSE)
    expect_equal(report$overall_health, "failed")
})

test_that("train_main all plants fail", {
    temp_artifact <- withr::local_tempdir()
    config <- gen_config(
        mode = "train",
        ids_usinas = c("USI1", "USI2"),
        janela = list("2025-07-01", "2025-09-30")
    )
    config$artifact <- temp_artifact
    config$input <- temp_artifact

    mockery::stub(train_main, "conectamock_pfv", function(...) NULL)
    mockery::stub(train_main, "get_usinas",
        function(...) gen_usinas(ids = c("USI1", "USI2")))
    mockery::stub(train_main, "get_dataset", function(...) {
        list(
            ger_obs = data.table::data.table(),
            corte = data.table::data.table(),
            irrad_prev = data.table::data.table()
        )
    })
    mockery::stub(train_main, "associa_nwp_usina",
        function(...) data.table::data.table())
    mockery::stub(train_main, "adicionar_passo_previsao",
        function(x, ...) x)
    mockery::stub(train_main, "ajustar_usina",
        function(iu, ...) stop("all fail"))
    mockery::stub(train_main, "write_model_artifact",
        function(...) invisible(NULL))

    expect_no_error(train_main(config))

    prov_files <- list.files(temp_artifact, "^provenance-.*\\.json$",
        full.names = TRUE)
    parsed <- jsonlite::fromJSON(prov_files[1], simplifyVector = FALSE)

    expect_equal(parsed$plant_status$USI1, "failed")
    expect_equal(parsed$plant_status$USI2, "failed")
    expect_equal(parsed$status, "failed")
})
