test_that("fit_model", {
    f <- fit_model

    test_that("fit_model valida que strategy e string escalar", {
        expect_error(f(123, NULL, NULL, NULL))
        expect_error(f(c("a", "b"), NULL, NULL, NULL))
        expect_error(f(NULL, NULL, NULL, NULL))
        expect_error(f(TRUE, NULL, NULL, NULL))
    })

    test_that("fit_model levanta erro para estrategia desconhecida", {
        expect_error(f("nonexistent", NULL, NULL, NULL), "nao implementado")
        expect_error(f("nonexistent", NULL, NULL, NULL), "nonexistent")
    })

    test_that("fit_model despacha para fit_linear_regression", {
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

        result <- f("linear_regression",
            dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty)
        )

        expect_true(inherits(result, "linear_regression_model"))
        expect_true(is.data.frame(result$parametros))
    })
})

test_that("predict_model", {
    f <- predict_model

    test_that("predict_model.default levanta erro com nome da classe", {
        fake_model <- structure(list(), class = "unknown_model_type")
        expect_error(f(fake_model), "nao implementado")
        expect_error(f(fake_model), "unknown_model_type")
    })

    test_that("predict_model.default levanta erro para lista sem classe", {
        expect_error(f(list(a = 1)), "nao implementado")
        expect_error(f(list(a = 1)), "list")
    })
})

test_that("model_metadata", {
    f <- model_metadata

    test_that("model_metadata.default levanta erro com nome da classe", {
        fake_model <- structure(list(), class = "unknown_model_type")
        expect_error(f(fake_model), "nao implementado")
        expect_error(f(fake_model), "unknown_model_type")
    })

    test_that("model_metadata.default levanta erro para lista sem classe", {
        expect_error(f(list(a = 1)), "nao implementado")
        expect_error(f(list(a = 1)), "list")
    })
})

test_that("custom model dispatch works with new API", {
    ns <- asNamespace("mhpfv")

    fit_custom <- function(dty, dtx, dty_bruta, ...) {
        structure(list(fitted = TRUE), class = "custom_model")
    }

    predict_model.custom_model <- function(model, ...) { # nolint: object_name_linter.
        list(predicted = TRUE)
    }

    model_metadata.custom_model <- function(model, ...) { # nolint: object_name_linter.
        list(name = "custom")
    }

    registerS3method("predict_model", "custom_model",
        predict_model.custom_model, envir = ns)
    registerS3method("model_metadata", "custom_model",
        model_metadata.custom_model, envir = ns)

    # fit_model uses get0() in the locked namespace; new fit functions cannot
    # be added via assign(). Mock fit_model to route "custom" to fit_custom.
    local_mocked_bindings(
        fit_model = function(strategy, dty, dtx, dty_bruta, ...) {
            stopifnot(is.character(strategy), length(strategy) == 1L)
            if (strategy == "custom") {
                return(fit_custom(dty = dty, dtx = dtx, dty_bruta = dty_bruta, ...))
            }
            fn_name <- paste0("fit_", strategy)
            fn <- get0(fn_name, envir = ns, mode = "function", inherits = FALSE)
            if (is.null(fn)) {
                stop("fit_model nao implementado para estrategia '", strategy, "'")
            }
            fn(dty = dty, dtx = dtx, dty_bruta = dty_bruta, ...)
        }
    )

    fit_result <- fit_model("custom", NULL, NULL, NULL)
    expect_true(fit_result$fitted)
    expect_true(inherits(fit_result, "custom_model"))

    pred_result <- predict_model(fit_result)
    expect_true(pred_result$predicted)

    meta_result <- model_metadata(fit_result)
    expect_equal(meta_result$name, "custom")
})

test_that("fit_linear_regression", {
    f <- fit_linear_regression

    test_that("fit_linear_regression retorna linear_regression_model", {
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

        result <- f(dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty))

        expect_true(inherits(result, "linear_regression_model"))
        expect_true(is.data.frame(result$parametros))
        expect_true("a" %in% names(result$parametros))
    })

    test_that("fit_linear_regression produz resultado identico a ajusta_regressao_ger_irrad", {
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

        via_fit <- f(dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty))

        expect_identical(direto, via_fit$parametros)
    })

    test_that("fit_model e fit_linear_regression produzem mesmo resultado", {
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

        via_fit_model <- fit_model("linear_regression",
            dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty)
        )
        via_direct <- f(dty = copy(dty), dtx = copy(dtx), dty_bruta = copy(dty))

        expect_identical(via_fit_model$parametros, via_direct$parametros)
        expect_equal(class(via_fit_model), class(via_direct))
    })

    test_that("fit_linear_regression com dados de teste reais", {
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

        via_fit <- f(
            dty = copy(geracao),
            dtx = copy(irrad_prev),
            dty_bruta = copy(geracao_bruta)
        )

        expect_identical(direto, via_fit$parametros)
        expect_true(inherits(via_fit, "linear_regression_model"))
    })
})

test_that("predict_model.linear_regression_model", {
    f <- predict_model

    test_that("predict_model.linear_regression_model delega para substitui_por_estimativas", {
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

        model_df <- data.frame(
            a = 0.2,
            b = 0,
            row.names = "06:00"
        )
        model <- structure(list(parametros = model_df), class = "linear_regression_model")
        lim_dados <- c(0, 100)

        direto <- substitui_por_estimativas(
            df_ger_usi = copy(df_ger_usi),
            df_irrad_prev = copy(df_irrad_prev),
            regressoes = model_df,
            lim_dados = lim_dados
        )

        via_dispatch <- f(
            model,
            df_ger_usi = copy(df_ger_usi),
            df_irrad_prev = copy(df_irrad_prev),
            lim_dados = lim_dados
        )

        expect_identical(direto, via_dispatch)
    })
})

test_that("model_metadata.linear_regression_model", {
    f <- model_metadata

    test_that("model_metadata.linear_regression_model retorna estrutura correta", {
        artifact <- gen_model_artifact()
        model <- artifact$model

        meta <- f(model)

        expect_true(is.list(meta))
        expect_equal(meta$type, "linear_regression")
        expect_equal(meta$n_slots, nrow(model$parametros))
        expect_equal(meta$n_valid_slots, sum(!is.na(model$parametros$a)))
        expect_true(inherits(meta$timestamp, "POSIXct"))
    })

    test_that("model_metadata.linear_regression_model trata coeficientes NA", {
        params <- data.frame(
            a = c(0.1, NA, 0.3, NA, 0.5),
            b = rep(0, 5),
            row.names = c("06:00", "06:30", "07:00", "07:30", "08:00")
        )
        model <- structure(list(parametros = params), class = "linear_regression_model")

        meta <- f(model)

        expect_equal(meta$n_slots, 5L)
        expect_equal(meta$n_valid_slots, 3L)
    })

    test_that("model_metadata.linear_regression_model valida parametros", {
        bad_model1 <- structure(
            list(parametros = data.frame(b = 1:3)),
            class = "linear_regression_model"
        )
        bad_model2 <- structure(
            list(parametros = list(a = 1:3)),
            class = "linear_regression_model"
        )

        expect_error(f(bad_model1))
        expect_error(f(bad_model2))
    })

    test_that("model_metadata.linear_regression_model retorna 0 valid_slots quando todos NA", {
        params <- data.frame(
            a = c(NA_real_, NA_real_, NA_real_),
            b = rep(0, 3),
            row.names = c("06:00", "06:30", "07:00")
        )
        model <- structure(list(parametros = params), class = "linear_regression_model")

        meta <- f(model)

        expect_equal(meta$n_slots, 3L)
        expect_equal(meta$n_valid_slots, 0L)
    })
})
