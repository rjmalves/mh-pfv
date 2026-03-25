test_that("new_model_strategy", {
    f <- new_model_strategy

    test_that("new_model_strategy cria objeto S3 valido", {
        s <- f("linear_regression")

        expect_true(inherits(s, "model_strategy"))
        expect_true(inherits(s, "linear_regression"))
        expect_equal(s$type, "linear_regression")
        expect_true(is.list(s$params))
        expect_equal(length(s$params), 0L)
    })

    test_that("new_model_strategy armazena parametros adicionais", {
        s <- f("linear_regression", alpha = 0.05, window = 10)

        expect_equal(s$params$alpha, 0.05)
        expect_equal(s$params$window, 10)
    })

    test_that("new_model_strategy possui classe dupla na ordem correta", {
        s <- f("custom_model")

        expect_equal(class(s), c("custom_model", "model_strategy"))
    })

    test_that("new_model_strategy valida tipo string", {
        expect_error(f(""))
        expect_error(f(123))
        expect_error(f(c("a", "b")))
        expect_error(f(NULL))
        expect_error(f(NA_character_))
    })
})

test_that("fit_model", {
    f <- fit_model

    test_that("fit_model.model_strategy levanta erro padrao", {
        s <- new_model_strategy("nonexistent_model")

        expect_error(f(s, NULL, NULL, NULL), "nao implementado")
        expect_error(f(s, NULL, NULL, NULL), "nonexistent_model")
    })
})

test_that("predict_model", {
    f <- predict_model

    test_that("predict_model.model_strategy levanta erro padrao", {
        s <- new_model_strategy("nonexistent_model")

        expect_error(f(s, NULL, NULL, NULL, NULL), "nao implementado")
        expect_error(f(s, NULL, NULL, NULL, NULL), "nonexistent_model")
    })
})

test_that("model_metadata", {
    f <- model_metadata

    test_that("model_metadata.model_strategy levanta erro padrao", {
        s <- new_model_strategy("nonexistent_model")

        expect_error(f(s, NULL), "nao implementado")
        expect_error(f(s, NULL), "nonexistent_model")
    })
})

test_that("dispatch S3 funciona para subclasse customizada", {
    s <- new_model_strategy("test_model")

    fit_model.test_model <- function(strategy, dty, dtx, dty_bruta, ...) { # nolint: object_name_linter.
        list(fitted = TRUE, type = strategy$type)
    }

    predict_model.test_model <- function(strategy, model, df_ger_usi, # nolint: object_name_linter.
        df_irrad_prev, lim_dados, ...) {
        list(predicted = TRUE)
    }

    model_metadata.test_model <- function(strategy, model, ...) { # nolint: object_name_linter.
        list(name = "test")
    }

    fit_result <- fit_model(s, NULL, NULL, NULL)
    expect_true(fit_result$fitted)
    expect_equal(fit_result$type, "test_model")

    pred_result <- predict_model(s, fit_result, NULL, NULL, NULL)
    expect_true(pred_result$predicted)

    meta_result <- model_metadata(s, fit_result)
    expect_equal(meta_result$name, "test")
})

test_that("linear_regression_strategy", {
    f <- linear_regression_strategy

    test_that("linear_regression_strategy cria objeto com classe dupla", {
        s <- f()

        expect_equal(class(s), c("linear_regression", "model_strategy"))
        expect_equal(s$type, "linear_regression")
        expect_true(is.list(s$params))
        expect_equal(length(s$params), 0L)
    })

    test_that("linear_regression_strategy repassa parametros", {
        s <- f(alpha = 0.01)

        expect_equal(s$params$alpha, 0.01)
    })
})

test_that("fit_model.linear_regression", {
    f <- fit_model

    test_that("fit_model.linear_regression produz resultado identico", {
        horarios <- seq(
            from = as.POSIXct("2025-01-01 06:00"),
            by = "1 day",
            length.out = 10
        )

        dtx <- data.table(
            id_usina = "U1",
            data_hora_previsao = horarios,
            valor = seq(10, 100, by = 10)
        )

        dty <- data.table(
            id_usina = "U1",
            data_hora_observacao = horarios,
            valor = seq(2, 20, by = 2)
        )

        direto <- ajusta_regressao_ger_irrad(
            dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty)
        )

        s <- linear_regression_strategy()
        via_strategy <- f(s, dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty))

        expect_identical(direto, via_strategy)
    })

    test_that("fit_model.linear_regression com dados de teste reais", {
        skip_if_not(dir.exists(test_path("data")))
        skip_if_no_zstd()

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
        dad_usi <- dt_usinas[id_usina == iu]
        ger_usi <- dataset$ger_obs[id_usina == iu]
        corte_obs <- dataset$corte[id_usina == iu]
        potencia <- dad_usi$capacidade_instalada_MW

        dt_irrad_prev_filt <- associa_nwp_usina(dt_usinas, dataset$irrad_prev)
        dt_irrad_prev_filt_n <- adicionar_passo_previsao(dt_irrad_prev_filt)
        irrad_prev <- dt_irrad_prev_filt_n[id_usina == iu & passo_prev == "D+0"]
        irrad_prev <- interpolar_30min(irrad_prev)

        geracao <- consiste_geracao_unit(
            dados_usina = dad_usi,
            geracao_usina = ger_usi,
            corte_obs = corte_obs,
            ordem_prioridade = config$ordem_prioridade_fontes,
            limite_dados = c(0, potencia * config$fator_tolerancia_limite_superior_geracao)
        )

        geracao[valor == 999, valor := NA]
        irrad_prev[valor == 999, valor := NA]
        geracao_bruta <- copy(geracao)

        if (!is.null(corte_obs)) {
            geracao <- aplica_cortes_em_geracao(
                dt_geracao_usina = copy(geracao),
                dt_cortes = copy(corte_obs)
            )
        }

        direto <- ajusta_regressao_ger_irrad(
            dty = copy(geracao),
            dtx = copy(irrad_prev),
            dty_bruta = copy(geracao_bruta)
        )

        s <- linear_regression_strategy()
        via_strategy <- f(
            s,
            dty = copy(geracao),
            dtx = copy(irrad_prev),
            dty_bruta = copy(geracao_bruta)
        )

        expect_identical(direto, via_strategy)
    })
})

test_that("predict_model.linear_regression", {
    f <- predict_model

    test_that("predict_model.linear_regression delega para substitui_por_estimativas", {
        datas <- seq(
            from = as.POSIXct("2025-01-01 06:00"),
            by = "1 day",
            length.out = 20
        )

        df_ger_usi <- data.table(
            id_usina = "U1",
            data_hora_observacao = datas,
            valor = c(rep(NA_real_, 10), seq(2, 20, by = 2)),
            status = 0L
        )

        df_irrad_prev <- data.table(
            id_usina = "U1",
            data_hora_previsao = datas,
            valor = seq(10, 200, by = 10)
        )

        model <- data.frame(
            a = 0.2,
            b = 0,
            row.names = "06:00"
        )
        lim_dados <- c(0, 100)

        direto <- substitui_por_estimativas(
            df_ger_usi = copy(df_ger_usi),
            df_irrad_prev = copy(df_irrad_prev),
            regressoes = model,
            lim_dados = lim_dados
        )

        s <- linear_regression_strategy()
        via_strategy <- f(
            s,
            model = model,
            df_ger_usi = copy(df_ger_usi),
            df_irrad_prev = copy(df_irrad_prev),
            lim_dados = lim_dados
        )

        expect_identical(direto, via_strategy)
    })
})

test_that("model_metadata.linear_regression", {
    f <- model_metadata

    test_that("model_metadata.linear_regression retorna estrutura correta", {
        model <- gen_model_artifact()$parametros
        s <- linear_regression_strategy()

        meta <- f(s, model)

        expect_true(is.list(meta))
        expect_equal(meta$type, "linear_regression")
        expect_equal(meta$n_slots, nrow(model))
        expect_equal(meta$n_valid_slots, sum(!is.na(model$a)))
        expect_true(inherits(meta$timestamp, "POSIXct"))
    })

    test_that("model_metadata.linear_regression trata coeficientes NA", {
        model <- data.frame(
            a = c(0.1, NA, 0.3, NA, 0.5),
            b = rep(0, 5),
            row.names = c("06:00", "06:30", "07:00", "07:30", "08:00")
        )
        s <- linear_regression_strategy()

        meta <- f(s, model)

        expect_equal(meta$n_slots, 5L)
        expect_equal(meta$n_valid_slots, 3L)
    })

    test_that("model_metadata.linear_regression valida coluna a", {
        s <- linear_regression_strategy()

        expect_error(f(s, data.frame(b = 1:3)))
        expect_error(f(s, list(a = 1:3)))
        expect_error(f(s, "not a data.frame"))
    })

    test_that("model_metadata.linear_regression retorna 0 valid_slots quando todos coeficientes sao NA", {
        model <- data.frame(
            a = c(NA_real_, NA_real_, NA_real_),
            b = rep(0, 3),
            row.names = c("06:00", "06:30", "07:00")
        )
        s <- linear_regression_strategy()

        meta <- f(s, model)

        expect_equal(meta$n_slots, 3L)
        expect_equal(meta$n_valid_slots, 0L)
    })
})
