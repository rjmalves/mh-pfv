test_that("build_artifact_metadata", {
    f <- build_artifact_metadata
    expect_true(is.function(f))

    test_that("build_artifact_metadata retorna estrutura correta", {
        model <- gen_model_artifact()$parametros
        s <- linear_regression_strategy()
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        meta <- f(s, model, cfg)

        expect_true(is.list(meta))
        expected_fields <- c(
            "type", "n_slots", "n_valid_slots",
            "timestamp", "package_version", "config_hash"
        )
        expect_true(all(expected_fields %in% names(meta)))
        expect_equal(meta$type, "linear_regression")
        expect_equal(meta$n_slots, nrow(model))
        expect_equal(meta$n_valid_slots, sum(!is.na(model$a)))
        expect_true(inherits(meta$timestamp, "POSIXct"))
        expect_true(is.character(meta$package_version))
        expect_true(nchar(meta$package_version) > 0L)
        expect_true(is.character(meta$config_hash))
        expect_true(nchar(meta$config_hash) > 0L)
    })

    test_that("build_artifact_metadata config hash e deterministico", {
        model <- gen_model_artifact()$parametros
        s <- linear_regression_strategy()
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        meta1 <- f(s, model, cfg)
        meta2 <- f(s, model, cfg)

        expect_equal(meta1$config_hash, meta2$config_hash)
    })

    test_that("build_artifact_metadata config hash difere com config diferente", {
        model <- gen_model_artifact()$parametros
        s <- linear_regression_strategy()
        cfg1 <- gen_config(janela = list("2025-07-01", "2025-09-30"))
        cfg2 <- gen_config(janela = list("2025-01-01", "2025-06-30"))

        meta1 <- f(s, model, cfg1)
        meta2 <- f(s, model, cfg2)

        expect_false(meta1$config_hash == meta2$config_hash)
    })

    test_that("build_artifact_metadata valida strategy", {
        model <- gen_model_artifact()$parametros
        cfg <- gen_config()

        expect_error(f("nao_strategy", model, cfg))
        expect_error(f(NULL, model, cfg))
    })

    test_that("build_artifact_metadata valida config", {
        model <- gen_model_artifact()$parametros
        s <- linear_regression_strategy()

        expect_error(f(s, model, "nao_lista"))
        expect_error(f(s, model, 42))
    })
})

test_that("normalize_config_for_hash", {
    f <- normalize_config_for_hash
    expect_true(is.function(f))

    test_that("normalize_config_for_hash seleciona campos relevantes", {
        cfg <- gen_config()
        cfg$extra_field <- "ignorado"

        result <- f(cfg)

        expect_false("extra_field" %in% names(result))
        expect_false("mode" %in% names(result))
        expect_false("input" %in% names(result))
        expect_true("janela" %in% names(result))
        expect_true("ids_usinas" %in% names(result))
    })

    test_that("normalize_config_for_hash ordena por nome", {
        cfg <- gen_config()
        result <- f(cfg)

        expect_equal(names(result), sort(names(result)))
    })

    test_that("normalize_config_for_hash e deterministico com ordem diferente", {
        cfg1 <- list(
            janela = c("2025-07-01", "2025-09-30"),
            ids_usinas = "USI1",
            ordem_prioridade_fontes = "PI"
        )
        cfg2 <- list(
            ordem_prioridade_fontes = "PI",
            ids_usinas = "USI1",
            janela = c("2025-07-01", "2025-09-30")
        )

        r1 <- f(cfg1)
        r2 <- f(cfg2)

        h1 <- digest::digest(r1, algo = "sha256")
        h2 <- digest::digest(r2, algo = "sha256")

        expect_equal(h1, h2)
    })
})

test_that("build_model_artifact", {
    f <- build_model_artifact
    expect_true(is.function(f))

    test_that("build_model_artifact retorna estrutura enriquecida", {
        s <- linear_regression_strategy()
        params <- gen_model_artifact_legacy()$parametros
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        result <- f("USI1", params, s, cfg)

        expect_true(is.list(result))
        expect_equal(names(result), c("id_usina", "parametros", "metadata"))
        expect_equal(result$id_usina, "USI1")
        expect_identical(result$parametros, params)
        expect_true(is.list(result$metadata))
    })

    test_that("build_model_artifact metadata contem todos os campos", {
        s <- linear_regression_strategy()
        params <- gen_model_artifact_legacy()$parametros
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        result <- f("USI1", params, s, cfg)

        expected_fields <- c(
            "type", "n_slots", "n_valid_slots",
            "timestamp", "package_version", "config_hash"
        )
        expect_true(all(expected_fields %in% names(result$metadata)))
    })
})

test_that("validate_artifact", {
    f <- validate_artifact
    expect_true(is.function(f))

    test_that("validate_artifact aceita artefato novo com metadata", {
        art <- gen_model_artifact()
        expect_invisible(f(art))
        expect_true(f(art))
    })

    test_that("validate_artifact aceita artefato legado com aviso", {
        art <- gen_model_artifact_legacy()
        expect_invisible(f(art))
        expect_true(f(art))
    })

    test_that("validate_artifact rejeita entrada nao-lista", {
        expect_error(f("nao_lista"), "Artefato deve ser uma lista")
        expect_error(f(42), "Artefato deve ser uma lista")
    })

    test_that("validate_artifact rejeita artefato sem id_usina", {
        art <- list(parametros = data.frame(a = 1, b = 0))
        expect_error(f(art), "id_usina")
    })

    test_that("validate_artifact rejeita id_usina nao-character", {
        art <- list(
            id_usina = 123,
            parametros = data.frame(a = 1, b = 0)
        )
        expect_error(f(art), "character escalar")
    })

    test_that("validate_artifact rejeita artefato sem parametros", {
        art <- list(id_usina = "USI1")
        expect_error(f(art), "parametros")
    })

    test_that("validate_artifact rejeita parametros nao-data.frame", {
        art <- list(id_usina = "USI1", parametros = list(a = 1))
        expect_error(f(art), "data.frame")
    })

    test_that("validate_artifact rejeita parametros sem coluna a", {
        art <- list(
            id_usina = "USI1",
            parametros = data.frame(b = 0, c = 1)
        )
        expect_error(f(art), "coluna 'a'")
    })

    test_that("validate_artifact coleta multiplos erros", {
        art <- list()
        err <- tryCatch(f(art), error = function(e) e$message)
        expect_true(grepl("id_usina", err))
        expect_true(grepl("parametros", err))
    })

    test_that("validate_artifact model$parametros funciona nos dois formatos", {
        novo <- gen_model_artifact()
        legado <- gen_model_artifact_legacy()

        expect_identical(novo$parametros, novo[[2]])
        expect_identical(legado$parametros, legado[[2]])
    })
})
