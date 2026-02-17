fit_model.test_strategy <- function(strategy, dty, dtx, dty_bruta, ...) {
    horas <- seq(5.0, 18.5, by = 0.5)
    nomes <- sprintf(
        "%02d:%02d",
        floor(horas),
        ifelse(horas %% 1 == 0.5, 30, 0)
    )
    data.frame(
        a = rep(0.5, length(horas)),
        b = rep(0, length(horas)),
        row.names = nomes
    )
}

predict_model.test_strategy <- function(strategy, model, df_ger_usi,
    df_irrad_prev, lim_dados, ...) {
    substitui_por_estimativas(df_ger_usi, df_irrad_prev, model, lim_dados)
}

model_metadata.test_strategy <- function(strategy, model, ...) {
    list(
        type = "test_strategy",
        n_slots = nrow(model),
        timestamp = Sys.time()
    )
}

registerS3method("fit_model", "test_strategy", fit_model.test_strategy,
    envir = asNamespace("mhpfv"))
registerS3method("predict_model", "test_strategy", predict_model.test_strategy,
    envir = asNamespace("mhpfv"))
registerS3method("model_metadata", "test_strategy", model_metadata.test_strategy,
    envir = asNamespace("mhpfv"))

test_that("fit_model dispatches to test_strategy mock", {
    s <- new_model_strategy("test_strategy")

    result <- fit_model(s, dty = NULL, dtx = NULL, dty_bruta = NULL)

    expect_true(is.data.frame(result))
    expect_true(all(c("a", "b") %in% names(result)))
    expect_true(all(result$a == 0.5))
    expect_true(all(result$b == 0))

    expected_horas <- seq(5.0, 18.5, by = 0.5)
    expected_names <- sprintf(
        "%02d:%02d",
        floor(expected_horas),
        ifelse(expected_horas %% 1 == 0.5, 30, 0)
    )
    expect_equal(rownames(result), expected_names)
})

test_that("model_metadata dispatches to test_strategy mock", {
    s <- new_model_strategy("test_strategy")
    model <- fit_model(s, NULL, NULL, NULL)

    meta <- model_metadata(s, model)

    expect_true(is.list(meta))
    expect_equal(meta$type, "test_strategy")
    expect_equal(meta$n_slots, nrow(model))
    expect_true(inherits(meta$timestamp, "POSIXct"))
})

test_that("train_main with test_strategy produces mock artifacts", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    strategy <- new_model_strategy("test_strategy")
    expect_no_error(train_main(config, strategy = strategy))

    expected_ids <- config$ids_usinas
    artifact_files <- file.path(
        temp_artifact, paste0(expected_ids, ".rds")
    )

    expect_true(all(file.exists(artifact_files)))

    for (af in artifact_files) {
        artifact <- readRDS(af)

        expect_true(is.list(artifact))
        expect_true(all(c("id_usina", "parametros") %in% names(artifact)))

        params <- artifact$parametros
        expect_true(is.data.frame(params))
        expect_true(all(params$a == 0.5))
        expect_true(all(params$b == 0))
    }
})

test_that("train_main with parallel = TRUE produces identical artifacts", {
    skip_if_not(dir.exists(test_path("data")))
    temp_seq <- withr::local_tempdir()
    temp_par <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config <- parse_config(config, conn)

    strategy <- new_model_strategy("test_strategy")

    config$artifact <- temp_seq
    train_main(config, strategy = strategy, parallel = FALSE)

    config$artifact <- temp_par
    withr::defer(future::plan("sequential"))
    train_main(config, strategy = strategy, parallel = TRUE)

    expected_ids <- config$ids_usinas
    for (iu in expected_ids) {
        fname <- paste0(iu, ".rds")
        art_seq <- readRDS(file.path(temp_seq, fname))
        art_par <- readRDS(file.path(temp_par, fname))

        expect_equal(art_seq$id_usina, art_par$id_usina)
        expect_equal(art_seq$parametros, art_par$parametros)
    }
})

test_that("test_strategy lifecycle: fit -> artifact -> predict_model", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    strategy <- new_model_strategy("test_strategy")
    train_main(config, strategy = strategy)

    iu <- config$ids_usinas[1]
    artifact <- readRDS(file.path(temp_artifact, paste0(iu, ".rds")))
    model <- artifact$parametros

    datas <- seq(
        from = as.POSIXct("2025-08-01 06:00", tz = "UTC"),
        by = "1 day",
        length.out = 20
    )

    df_ger_usi <- data.table(
        id_usina = iu,
        data_hora_observacao = datas,
        valor = c(rep(NA_real_, 10), seq(2, 20, by = 2)),
        status = 0L
    )

    df_irrad_prev <- data.table(
        id_usina = iu,
        data_hora_previsao = datas,
        valor = seq(10, 200, by = 10)
    )

    lim_dados <- c(0, 100)

    result <- predict_model(
        strategy,
        model = model,
        df_ger_usi = copy(df_ger_usi),
        df_irrad_prev = copy(df_irrad_prev),
        lim_dados = lim_dados
    )

    expect_true(data.table::is.data.table(result))
    expect_true("valor" %in% names(result))
})
