test_that("validate_input", {
    f <- validate_input

    test_that("validate_input aceita geracao_observada valida", {
        dt <- gen_geracao_observada(ids = "USI1")
        expect_true(f(dt, "geracao_observada"))
    })

    test_that("validate_input aceita irradiancia_prevista valida", {
        dt <- gen_irradiancia_prevista(ids = "USI1")
        expect_true(f(dt, "irradiancia_prevista"))
    })

    test_that("validate_input aceita corte_observado valido", {
        dt <- gen_corte_observado(ids = "USI1")
        expect_true(f(dt, "corte_observado"))
    })

    test_that("validate_input aceita usinas valida", {
        dt <- gen_usinas(n = 2L)
        expect_true(f(dt, "usinas"))
    })

    test_that("validate_input aceita melhor_historico_geracao valido", {
        dt <- gen_mhg(ids = "USI1")
        expect_true(f(dt, "melhor_historico_geracao"))
    })

    test_that("validate_input detecta coluna ausente em geracao_observada", {
        dt <- gen_geracao_observada(ids = "USI1")
        dt[, valor := NULL]
        expect_error(f(dt, "geracao_observada"), "valor")
    })

    test_that("validate_input detecta coluna ausente em irradiancia_prevista", {
        dt <- gen_irradiancia_prevista(ids = "USI1")
        dt[, valor := NULL]
        expect_error(f(dt, "irradiancia_prevista"), "valor")
    })

    test_that("validate_input detecta coluna ausente em corte_observado", {
        dt <- gen_corte_observado(ids = "USI1")
        dt[, valor := NULL]
        expect_error(f(dt, "corte_observado"), "valor")
    })

    test_that("validate_input detecta coluna ausente em usinas", {
        dt <- gen_usinas(n = 2L)
        dt[, id_usina := NULL]
        expect_error(f(dt, "usinas"), "id_usina")
    })

    test_that("validate_input detecta coluna ausente em melhor_historico_geracao", {
        dt <- gen_mhg(ids = "USI1")
        dt[, valor := NULL]
        expect_error(f(dt, "melhor_historico_geracao"), "valor")
    })

    test_that("validate_input detecta multiplas colunas ausentes", {
        dt <- gen_geracao_observada(ids = "USI1")
        dt[, c("valor", "id_usina") := NULL]
        expect_error(f(dt, "geracao_observada"), "valor")
        expect_error(f(dt, "geracao_observada"), "id_usina")
    })

    test_that("validate_input detecta tipo errado", {
        dt <- gen_geracao_observada(ids = "USI1")
        dt[, valor := as.character(valor)]
        expect_error(f(dt, "geracao_observada"), "valor.*numeric.*character")
    })

    test_that("validate_input detecta NA em coluna-chave", {
        dt <- gen_geracao_observada(ids = "USI1")
        dt[1, id_usina := NA_character_]
        expect_error(f(dt, "geracao_observada"), "id_usina.*NA")
    })

    test_that("validate_input detecta NA em data_hora_observacao", {
        dt <- gen_geracao_observada(ids = "USI1")
        dt[1:3, data_hora_observacao := as.POSIXct(NA)]
        expect_error(f(dt, "geracao_observada"), "data_hora_observacao.*3.*NA")
    })

    test_that("validate_input aceita colunas extras", {
        dt <- gen_geracao_observada(ids = "USI1")
        dt[, extra_col := 999]
        expect_true(f(dt, "geracao_observada"))
    })

    test_that("validate_input aceita data.table vazio", {
        dt <- data.table(
            id_fonte_observacao = character(0),
            id_usina = character(0),
            data_hora_observacao = as.POSIXct(character(0)),
            valor = numeric(0)
        )
        expect_true(f(dt, "geracao_observada"))
    })

    test_that("validate_input levanta erro para schema desconhecido", {
        dt <- data.table(x = 1)
        expect_error(f(dt, "inexistente"), "Schema desconhecido.*inexistente")
    })

    test_that("validate_input coleta todos os erros de uma vez", {
        dt <- data.table(
            id_fonte_observacao = 123,
            data_hora_observacao = "2025-01-01"
        )
        err <- tryCatch(f(dt, "geracao_observada"), error = conditionMessage)
        expect_match(err, "id_usina")
        expect_match(err, "valor")
        expect_match(err, "id_fonte_observacao.*character")
        expect_match(err, "data_hora_observacao.*POSIXct")
    })

    test_that("validate_input aceita integer como numeric", {
        dt <- gen_corte_observado(ids = "USI1")
        expect_true(is.integer(dt$valor))
        expect_true(f(dt, "corte_observado"))
    })

    test_that("validate_input aceita numeric como integer no schema", {
        dt <- gen_mhg(ids = "USI1")
        dt[, status := as.numeric(status)]
        expect_true(f(dt, "melhor_historico_geracao"))
    })

    test_that("validate_input valida tipo de dt", {
        expect_error(f(data.frame(x = 1), "usinas"))
    })

    test_that("validate_input valida tipo de schema_name", {
        dt <- gen_usinas()
        expect_error(f(dt, 123))
        expect_error(f(dt, c("usinas", "usinas")))
    })

    test_that("validate_input levanta erro para schema_name vazio", {
        dt <- gen_usinas()
        expect_error(f(dt, ""), "Schema desconhecido")
    })
})

test_that("validate_all_inputs", {
    f <- validate_all_inputs

    test_that("validate_all_inputs aceita dados validos dos generators", {
        ids <- c("USI1", "USI2")
        dt_usinas <- gen_usinas(ids = ids)

        dataset <- list(
            ger_obs = gen_geracao_observada(ids = ids),
            corte = gen_corte_observado(ids = ids),
            irrad_prev = gen_irradiancia_prevista(ids = ids),
            mhg = gen_mhg(ids = ids),
            mhg_sem_cortes = gen_mhg(ids = ids)
        )

        expect_true(f(dataset, dt_usinas))
    })

    test_that("validate_all_inputs falha se usinas invalida", {
        ids <- "USI1"
        dt_usinas <- gen_usinas(ids = ids)
        dt_usinas[, id_usina := NULL]

        dataset <- list(
            ger_obs = gen_geracao_observada(ids = ids),
            corte = gen_corte_observado(ids = ids),
            irrad_prev = gen_irradiancia_prevista(ids = ids),
            mhg = gen_mhg(ids = ids),
            mhg_sem_cortes = gen_mhg(ids = ids)
        )

        expect_error(f(dataset, dt_usinas), "id_usina")
    })

    test_that("validate_all_inputs falha se ger_obs invalida", {
        ids <- "USI1"
        dt_usinas <- gen_usinas(ids = ids)

        dt_ger <- gen_geracao_observada(ids = ids)
        dt_ger[, valor := NULL]

        dataset <- list(
            ger_obs = dt_ger,
            corte = gen_corte_observado(ids = ids),
            irrad_prev = gen_irradiancia_prevista(ids = ids),
            mhg = gen_mhg(ids = ids),
            mhg_sem_cortes = gen_mhg(ids = ids)
        )

        expect_error(f(dataset, dt_usinas), "valor")
    })

    test_that("validate_all_inputs falha no primeiro componente invalido", {
        ids <- "USI1"
        dt_usinas <- gen_usinas(ids = ids)

        dt_ger <- gen_geracao_observada(ids = ids)
        dt_ger[, valor := NULL]

        dt_irrad <- gen_irradiancia_prevista(ids = ids)
        dt_irrad[, valor := NULL]

        dataset <- list(
            ger_obs = dt_ger,
            corte = gen_corte_observado(ids = ids),
            irrad_prev = dt_irrad,
            mhg = gen_mhg(ids = ids),
            mhg_sem_cortes = gen_mhg(ids = ids)
        )

        expect_error(f(dataset, dt_usinas), "geracao_observada.*valor")
    })

    test_that("validate_all_inputs com dados de teste do disco", {
        conn <- conectamock_pfv(testthat::test_path("data"))
        usinas_ids <- get_usinas(conn)$id_usina
        dt_usinas <- get_usinas(conn)

        conf <- gen_config("predict")
        conf$ids_usinas <- usinas_ids
        conf$janela <- Sys.Date() - c(91, 1)

        dataset <- get_dataset(conf, conn)

        expect_true(f(dataset, dt_usinas))
    })
})

test_that("get_schema", {
    f <- get_schema

    test_that("get_schema retorna schema valido", {
        schema <- f("geracao_observada")
        expect_true(is.list(schema))
        expect_true("columns" %in% names(schema))
        expect_true("keys" %in% names(schema))
    })

    test_that("get_schema levanta erro para schema desconhecido", {
        expect_error(f("nao_existe"), "Schema desconhecido.*nao_existe")
    })

    test_that("get_schema retorna todos os schemas definidos", {
        schema_names <- c(
            "geracao_observada", "irradiancia_prevista",
            "corte_observado", "usinas", "melhor_historico_geracao"
        )
        for (sn in schema_names) {
            schema <- f(sn)
            expect_true(is.list(schema$columns))
            expect_true(is.character(schema$keys))
        }
    })
})

test_that("check_type", {
    f <- check_type

    test_that("check_type valida numeric", {
        expect_true(f(1.5, "numeric"))
        expect_true(f(1L, "numeric"))
        expect_false(f("a", "numeric"))
    })

    test_that("check_type valida character", {
        expect_true(f("abc", "character"))
        expect_false(f(123, "character"))
    })

    test_that("check_type valida POSIXct", {
        expect_true(f(Sys.time(), "POSIXct"))
        expect_false(f("2025-01-01", "POSIXct"))
        expect_false(f(as.Date("2025-01-01"), "POSIXct"))
    })

    test_that("check_type valida integer de forma leniente", {
        expect_true(f(1L, "integer"))
        expect_true(f(1.0, "integer"))
        expect_false(f("1", "integer"))
    })

    test_that("check_type levanta erro para tipo desconhecido", {
        expect_error(f(1, "factor"), "Tipo desconhecido")
    })
})
