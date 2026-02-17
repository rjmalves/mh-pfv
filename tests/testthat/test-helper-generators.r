test_that("gen_config returns valid default config", {
    conf <- gen_config()
    expect_type(conf, "list")
    expect_true(all(config_names() %in% names(conf)))
    expect_null(valida_nomes_config(conf))
    expect_null(valida_tipos_config(conf))
})

test_that("gen_config respects mode argument", {
    conf_train <- gen_config("train")
    expect_equal(conf_train$mode, "train")

    conf_predict <- gen_config("predict")
    expect_equal(conf_predict$mode, "predict")
})

test_that("gen_config applies overrides", {
    conf <- gen_config(mode = "predict", input = "/custom/path")
    expect_equal(conf$input, "/custom/path")
    expect_equal(conf$mode, "predict")
})

test_that("gen_usinas returns correct columns and types", {
    dt <- gen_usinas()
    expected_cols <- c(
        "id_usina", "latitude", "longitude",
        "capacidade_instalada_MW",
        "data_inicio_operacao_comercial"
    )
    expect_equal(names(dt), expected_cols)
    expect_true(data.table::is.data.table(dt))
    expect_true(is.character(dt$id_usina))
    expect_true(is.numeric(dt$latitude))
    expect_true(is.numeric(dt$longitude))
    expect_true(is.numeric(dt$capacidade_instalada_MW))
    expect_s3_class(dt$data_inicio_operacao_comercial, "POSIXct")
})

test_that("gen_usinas respects n argument", {
    dt <- gen_usinas(n = 5)
    expect_equal(nrow(dt), 5)
    expect_equal(dt$id_usina, paste0("USI", 1:5))
})

test_that("gen_usinas respects ids argument", {
    dt <- gen_usinas(ids = c("AAA", "BBB", "CCC"))
    expect_equal(nrow(dt), 3)
    expect_equal(dt$id_usina, c("AAA", "BBB", "CCC"))
})

test_that("gen_usinas coordinates are in Brazilian solar belt", {
    dt <- gen_usinas(n = 10)
    expect_true(all(dt$latitude >= -25 & dt$latitude <= -12))
    expect_true(all(dt$longitude >= -50 & dt$longitude <= -38))
})

test_that("gen_geracao_observada returns correct columns and types", {
    dt <- gen_geracao_observada()
    expected_cols <- c(
        "id_fonte_observacao", "id_usina",
        "data_hora_observacao", "valor", "status"
    )
    expect_equal(names(dt), expected_cols)
    expect_true(data.table::is.data.table(dt))
    expect_true(is.character(dt$id_fonte_observacao))
    expect_true(is.character(dt$id_usina))
    expect_s3_class(dt$data_hora_observacao, "POSIXct")
    expect_true(is.numeric(dt$valor))
    expect_true(is.integer(dt$status))
})

test_that("gen_geracao_observada timestamps are UTC", {
    dt <- gen_geracao_observada()
    expect_equal(attr(dt$data_hora_observacao, "tzone"), "UTC")
})

test_that("gen_geracao_observada normal pattern has zeros at night", {
    dt <- gen_geracao_observada(pattern = "normal")
    hours <- data.table::hour(dt$data_hora_observacao)
    night_vals <- dt[hours >= 19 | hours < 5, valor]
    expect_true(all(night_vals == 0))
})

test_that("gen_geracao_observada frozen pattern has constant daytime", {
    dt <- gen_geracao_observada(pattern = "frozen")
    hours <- data.table::hour(dt$data_hora_observacao)
    day_vals <- dt[hours >= 5 & hours <= 18, valor]
    expect_true(all(day_vals == 10.0))
})

test_that("gen_geracao_observada missing pattern has NAs", {
    dt <- gen_geracao_observada(pattern = "missing")
    expect_true(any(is.na(dt$valor)))
    na_frac <- sum(is.na(dt$valor)) / nrow(dt)
    expect_true(na_frac > 0.05)
})

test_that("gen_geracao_observada all_na pattern is all NA", {
    dt <- gen_geracao_observada(pattern = "all_na")
    expect_true(all(is.na(dt$valor)))
})

test_that("gen_geracao_observada rejects invalid pattern", {
    expect_error(gen_geracao_observada(pattern = "invalid"))
})

test_that("gen_geracao_observada handles multiple ids and fontes", {
    dt <- gen_geracao_observada(ids = c("A", "B"), fontes = c("PI", "CCEE"))
    n_combos <- length(unique(dt$id_usina)) *
        length(unique(dt$id_fonte_observacao))
    expect_equal(n_combos, 4)
})

test_that("gen_irradiancia_prevista returns correct columns and types", {
    dt <- gen_irradiancia_prevista()
    expected_cols <- c(
        "id_modelo_nwp", "latitude", "longitude",
        "data_hora_rodada", "data_hora_previsao", "valor"
    )
    expect_equal(names(dt), expected_cols)
    expect_true(data.table::is.data.table(dt))
    expect_true(is.character(dt$id_modelo_nwp))
    expect_true(is.numeric(dt$latitude))
    expect_true(is.numeric(dt$longitude))
    expect_s3_class(dt$data_hora_rodada, "POSIXct")
    expect_s3_class(dt$data_hora_previsao, "POSIXct")
    expect_true(is.numeric(dt$valor))
})

test_that("gen_irradiancia_prevista has realistic solar curve", {
    dt <- gen_irradiancia_prevista()
    expect_true(all(dt$valor >= 0))
    expect_true(max(dt$valor) <= 1000)
    hours <- data.table::hour(dt$data_hora_previsao)
    night_vals <- dt[hours >= 19 | hours < 5, valor]
    expect_true(all(night_vals == 0))
})

test_that("gen_irradiancia_prevista handles multiple ids", {
    dt <- gen_irradiancia_prevista(ids = c("USI1", "USI2"))
    coords <- unique(dt[, .(latitude, longitude)])
    expect_equal(nrow(coords), 2)
})

test_that("gen_corte_observado returns correct columns and types", {
    dt <- gen_corte_observado()
    expected_cols <- c("id_usina", "data_hora_observacao", "valor")
    expect_equal(names(dt), expected_cols)
    expect_true(data.table::is.data.table(dt))
    expect_true(is.character(dt$id_usina))
    expect_s3_class(dt$data_hora_observacao, "POSIXct")
    expect_true(is.integer(dt$valor))
})

test_that("gen_corte_observado values are 0 or 1", {
    dt <- gen_corte_observado()
    expect_true(all(dt$valor %in% c(0L, 1L)))
})

test_that("gen_corte_observado respects frac_corte", {
    dt <- gen_corte_observado(frac_corte = 0.5, seed = 123L)
    frac <- mean(dt$valor)
    expect_true(frac > 0.3 && frac < 0.7)

    dt_zero <- gen_corte_observado(frac_corte = 0.0)
    expect_true(all(dt_zero$valor == 0L))
})

test_that("gen_mhg returns correct columns and types", {
    dt <- gen_mhg()
    expected_cols <- c(
        "id_fonte_observacao", "id_usina",
        "data_hora_observacao", "valor", "status"
    )
    expect_equal(names(dt), expected_cols)
    expect_true(data.table::is.data.table(dt))
    expect_true(is.character(dt$id_fonte_observacao))
    expect_true(is.character(dt$id_usina))
    expect_s3_class(dt$data_hora_observacao, "POSIXct")
    expect_true(is.numeric(dt$valor))
    expect_true(is.integer(dt$status))
})

test_that("gen_mhg has status values 1-4", {
    dt <- gen_mhg()
    expect_true(all(dt$status %in% 1L:4L))
})

test_that("gen_mhg id_fonte_observacao is Consis", {
    dt <- gen_mhg()
    expect_true(all(dt$id_fonte_observacao == "Consis"))
})

test_that("gen_model_artifact returns correct structure", {
    art <- gen_model_artifact()
    expect_type(art, "list")
    expect_equal(art$id_usina, "USI1")
    expect_true(is.data.frame(art$parametros))
    expect_true(all(c("a", "b") %in% names(art$parametros)))
})

test_that("gen_model_artifact has 28 half-hour slots", {
    art <- gen_model_artifact()
    expect_equal(nrow(art$parametros), 28)
    expect_equal(rownames(art$parametros)[1], "05:00")
    expect_equal(rownames(art$parametros)[28], "18:30")
})

test_that("gen_model_artifact coefficients are in expected range", {
    art <- gen_model_artifact()
    expect_true(all(art$parametros$a >= 0.01))
    expect_true(all(art$parametros$a <= 0.05))
    expect_true(all(art$parametros$b == 0))
})

test_that("gen_model_artifact respects id_usina argument", {
    art <- gen_model_artifact(id_usina = "CUSTOM1")
    expect_equal(art$id_usina, "CUSTOM1")
})
