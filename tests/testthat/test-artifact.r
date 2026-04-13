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
        model <- gen_model_artifact()$model
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        result <- f("USI1", model, cfg)

        expect_true(is.list(result))
        expect_equal(names(result), c("id_usina", "model", "metadata"))
        expect_equal(result$id_usina, "USI1")
        expect_identical(result$model, model)
        expect_true(is.list(result$metadata))
    })

    test_that("build_model_artifact metadata contem todos os campos", {
        model <- gen_model_artifact()$model
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        result <- f("USI1", model, cfg)

        expected_fields <- c(
            "type", "n_slots", "n_valid_slots",
            "timestamp", "package_version", "config_hash"
        )
        expect_true(all(expected_fields %in% names(result$metadata)))
    })

    test_that("build_model_artifact config hash e deterministico", {
        model <- gen_model_artifact()$model
        cfg <- gen_config(janela = list("2025-07-01", "2025-09-30"))

        result1 <- f("USI1", model, cfg)
        result2 <- f("USI1", model, cfg)

        expect_equal(result1$metadata$config_hash, result2$metadata$config_hash)
    })

    test_that("build_model_artifact config hash difere com config diferente", {
        model <- gen_model_artifact()$model
        cfg1 <- gen_config(janela = list("2025-07-01", "2025-09-30"))
        cfg2 <- gen_config(janela = list("2025-01-01", "2025-06-30"))

        result1 <- f("USI1", model, cfg1)
        result2 <- f("USI1", model, cfg2)

        expect_false(result1$metadata$config_hash == result2$metadata$config_hash)
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
        art <- list(model = structure(
            list(parametros = data.frame(a = 1)),
            class = "linear_regression_model"
        ))
        expect_error(f(art), "id_usina")
    })

    test_that("validate_artifact rejeita id_usina nao-character", {
        art <- list(
            id_usina = 123,
            model = structure(list(parametros = data.frame(a = 1)),
                class = "linear_regression_model")
        )
        expect_error(f(art), "character escalar")
    })

    test_that("validate_artifact rejeita artefato sem model", {
        art <- list(id_usina = "USI1")
        expect_error(f(art), "model")
    })

    test_that("validate_artifact rejeita model nao-lista", {
        art <- list(id_usina = "USI1", model = "not_a_list")
        expect_error(f(art), "lista")
    })

    test_that("validate_artifact coleta multiplos erros", {
        art <- list()
        err <- tryCatch(f(art), error = function(e) e$message)
        expect_true(grepl("id_usina", err))
        expect_true(grepl("model", err))
    })

    test_that("validate_artifact model acessivel em ambos formatos", {
        novo <- gen_model_artifact()
        legado <- gen_model_artifact_legacy()

        expect_identical(novo$model, novo[[2]])
        expect_identical(legado$model, legado[[2]])
    })
})
