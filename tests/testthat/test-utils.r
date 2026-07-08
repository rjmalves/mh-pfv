test_that("coloca_na_antes_inicio", {
    dt1 <- data.table::data.table(
        id_usina = c("U1", "U1", "U1"),
        data_hora_observacao = as.POSIXct(c(
            "2020-01-01 00:00:00",
            "2020-01-02 00:00:00",
            "2020-01-03 00:00:00"
        )),
        valor = c(10, 20, 30)
    )

    dados_usina1 <- data.table::data.table(
        id_usina = "U1",
        data_inicio_operacao_comercial = as.POSIXct("2020-01-02 00:00:00")
    )

    res1 <- coloca_na_antes_inicio(dt1, dados_usina1)

    expect_equal(res1$valor, c(NA_real_, 20, 30))

    dt2 <- data.table::data.table(
        id_usina = c("U2", "U2"),
        data_hora_observacao = as.POSIXct(c(
            "2021-05-10 12:00:00",
            "2021-05-11 12:00:00"
        )),
        valor = c(5, 7)
    )

    dados_usina2 <- data.table::data.table(
        id_usina = "U2",
        data_inicio_operacao_comercial = as.POSIXct("2021-05-01 00:00:00")
    )

    res2 <- coloca_na_antes_inicio(dt2, dados_usina2)

    expect_equal(res2$valor, c(5, 7))

    dt3 <- data.table::data.table(
        id_usina = c("A", "A", "B", "B"),
        data_hora_observacao = as.POSIXct(c(
            "2019-01-01 00:00:00",
            "2019-01-05 00:00:00",
            "2020-06-10 00:00:00",
            "2020-06-12 00:00:00"
        )),
        valor = c(1, 2, 3, 4)
    )

    dados_usina3 <- data.table::data.table(
        id_usina = c("A", "B"),
        data_inicio_operacao_comercial = as.POSIXct(c(
            "2019-01-03 00:00:00",
            "2020-06-11 00:00:00"
        ))
    )

    res3 <- coloca_na_antes_inicio(dt3, dados_usina3)

    expect_equal(
        res3$valor,
        c(NA_real_, 2, NA_real_, 4)
    )

    dt4 <- data.table::data.table(
        id_usina = c("X", "X"),
        data_hora_observacao = as.POSIXct(c(
            "2022-01-01 00:00:00",
            "2022-01-02 00:00:00"
        )),
        valor = c(10, 20)
    )

    dados_usina4 <- data.table::data.table(
        id_usina = "Z",
        data_inicio_operacao_comercial = as.POSIXct("2022-01-01 00:00:00")
    )

    res4 <- coloca_na_antes_inicio(dt4, dados_usina4)

    expect_equal(res4$valor, c(10, 20))

    dt5 <- data.table::data.table(
        id_usina = c("U", "U"),
        data_hora_observacao = as.POSIXct(c(
            "2021-01-01 00:00:00",
            "2021-01-10 00:00:00"
        )),
        valor = c(NA_real_, 5)
    )

    dados_usina5 <- data.table::data.table(
        id_usina = "U",
        data_inicio_operacao_comercial = as.POSIXct("2021-01-05 00:00:00")
    )

    res5 <- coloca_na_antes_inicio(dt5, dados_usina5)

    expect_equal(res5$valor, c(NA_real_, 5))
})


test_that("checa_valores_faltantes", {
    df <- data.frame(
        id_fonte_observacao = c("A", "A"),
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(10, 20),
        id_usina = c(1, 1)
    )
    res <- checa_valores_faltantes(df)
    expect_s3_class(res, "data.table")

    dt2 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(NaN, 5),
        id_usina = 1
    )
    res2 <- checa_valores_faltantes(dt2)
    expect_true(is.na(res2$valor[1]))
    expect_equal(res2$valor[2], 5)

    dt3 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(999, 1),
        id_usina = 1
    )
    res3 <- checa_valores_faltantes(dt3)
    expect_true(is.na(res3$valor[1]))
    expect_equal(res3$valor[2], 1)

    dt4 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 01:00:00")),
        valor = c(1, 2),
        id_usina = 1
    )
    res4 <- checa_valores_faltantes(dt4)
    expect_equal(nrow(res4), 3)
    expect_true(is.na(res4$valor[2]))

    dt5 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(1, 2),
        id_usina = 10
    )
    res5 <- checa_valores_faltantes(dt5)
    expect_equal(unique(res5$id_usina), 10)
})


test_that("combina_dados_tempo", {
    dt1 <- data.table(
        id_usina = c(1, 1),
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(10, 20),
        status = c(1, 1)
    )
    dt2 <- data.table(
        id_usina = 1,
        data_hora_observacao = as.POSIXct("2020-01-01 00:30:00"),
        valor = 25,
        status = 2
    )
    res <- combina_dados_tempo(dt1, dt2)
    expect_s3_class(res, "data.table")
    expect_equal(res$valor[res$data_hora_observacao == as.POSIXct("2020-01-01 00:30:00")], 25)
    expect_equal(res$status[res$data_hora_observacao == as.POSIXct("2020-01-01 00:30:00")], 2)
    expect_equal(res$valor[res$data_hora_observacao == as.POSIXct("2020-01-01 00:00:00")], 10)
    expect_equal(res$status[res$data_hora_observacao == as.POSIXct("2020-01-01 00:00:00")], 1)
    expect_true(all(res$id_fonte_observacao == "Consis"))
    expect_equal(res$id_usina, sort(res$id_usina))
    expect_equal(res$data_hora_observacao, sort(res$data_hora_observacao))

    dt1b <- data.table(
        id_usina = c(1, 2),
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:00:00")),
        valor = c(10, 5),
        status = c(1, 1)
    )
    dt2b <- data.table(
        id_usina = 2,
        data_hora_observacao = as.POSIXct("2020-01-01 00:00:00"),
        valor = 7,
        status = 2
    )
    res2 <- combina_dados_tempo(dt1b, dt2b)
    expect_equal(res2$valor[res2$id_usina == 2], 7)
    expect_equal(res2$status[res2$id_usina == 2], 2)
})


test_that("associa_nwp_usina", {
    dt_usinas <- data.table(
        id_usina = c(1, 2),
        latitude = c(-20, -19.9),
        longitude = c(-45, -44.9)
    )

    dt_irrad_prev <- data.table(
        id_modelo_nwp = "GFS",
        latitude = c(-20.0, -19.9, -19.95),
        longitude = c(-45.0, -44.9, -44.95),
        data_hora_previsao = as.POSIXct(
            c(
                "2025-10-03 00:00:00",
                "2025-10-03 00:30:00",
                "2025-10-03 01:00:00"
            )
        ),
        data_hora_rodada = as.POSIXct(c(
            "2025-10-02 12:00:00",
            "2025-10-02 12:00:00",
            "2025-10-02 12:00:00"
        )),
        irradiancia = c(100, 120, 110)
    )

    res1 <- associa_nwp_usina(dt_usinas, dt_irrad_prev)
    expect_s3_class(res1, "data.table")

    usina1_coord <- res1[id_usina == 1, .(latitude, longitude)]
    usina2_coord <- res1[id_usina == 2, .(latitude, longitude)]
    expect_true(all(usina1_coord$latitude == -20))
    expect_true(all(usina1_coord$longitude == -45))
    expect_true(all(usina2_coord$latitude == -19.9))
    expect_true(all(usina2_coord$longitude == -44.9))

    expect_true("id_usina" %in% names(res1))

    res2 <- adicionar_passo_previsao(res1)
    expect_true("passo_prev" %in% names(res2))
    expect_equal(res2$passo_prev[1], "D+1")

    dif_dias <- as.integer(as.Date(res2$data_hora_previsao) - as.Date(res2$data_hora_rodada))
    expect_equal(as.integer(sub("D+", "", res2$passo_prev)), dif_dias)

    expect_true(all(c(
        "id_modelo_nwp", "latitude", "longitude", "data_hora_previsao",
        "data_hora_rodada", "irradiancia"
    ) %in% names(res2)))
})


test_that("adicionar_passo_previsao", {
    dt1 <- data.table(
        data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
        data_hora_previsao = as.POSIXct("2025-08-03 12:00:00")
    )
    res1 <- adicionar_passo_previsao(copy(dt1))
    expect_equal(res1$passo_prev, "D+0")

    dt2 <- data.table(
        data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
        data_hora_previsao = as.POSIXct("2025-08-04 00:00:00")
    )
    res2 <- adicionar_passo_previsao(copy(dt2))
    expect_equal(res2$passo_prev, "D+1")

    dt3 <- data.table(
        data_hora_rodada = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 00:00:00", "2025-08-03 00:00:00")),
        data_hora_previsao = as.POSIXct(c("2025-08-03 03:00:00", "2025-08-04 03:00:00", "2025-08-05 03:00:00"))
    )
    res3 <- adicionar_passo_previsao(copy(dt3))
    expect_equal(res3$passo_prev, c("D+0", "D+1", "D+2"))

    dt4 <- data.table(
        data_hora_rodada = c("2025-08-03 00:00:00"),
        data_hora_previsao = c("2025-08-05 00:00:00")
    )
    res4 <- adicionar_passo_previsao(copy(dt4))
    expect_equal(res4$passo_prev, "D+2")

    dt5 <- data.table(
        id = 1:2,
        data_hora_rodada = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 00:00:00")),
        data_hora_previsao = as.POSIXct(c("2025-08-03 01:00:00", "2025-08-04 01:00:00"))
    )
    res5 <- adicionar_passo_previsao(copy(dt5))
    expect_true("passo_prev" %in% names(res5))
    expect_equal(ncol(res5), ncol(dt5) + 1)
})


test_that("interpolar_30min", {
    dt1 <- data.table(
        id_modelo_nwp = rep("GFS", 2),
        id_usina = rep("USINA_A", 2),
        latitude = -25,
        longitude = -48.5,
        data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
        data_hora_previsao = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 01:00:00")),
        valor = c(10, 20),
        passo_prev = rep("D+0", 2)
    )
    res1 <- interpolar_30min(copy(dt1))
    expect_s3_class(res1, "data.table")
    expect_equal(nrow(res1), 3)
    expect_equal(res1$valor[2], 15)
    expect_equal(names(res1), names(dt1))

    dt2 <- data.table(
        id_modelo_nwp = rep("GFS", 3),
        id_usina = rep("USINA_A", 3),
        latitude = -25,
        longitude = -48.5,
        data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
        data_hora_previsao = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 01:00:00", "2025-08-03 02:00:00")),
        valor = c(10, 20, 30),
        passo_prev = rep("D+0", 3)
    )
    res2 <- interpolar_30min(copy(dt2))
    expect_equal(nrow(res2), 5)
    expect_equal(res2$valor[2], 15)
    expect_equal(res2$valor[4], 25)

    dt3 <- rbind(
        data.table(
            id_modelo_nwp = "GFS", id_usina = "A", latitude = -25, longitude = -48,
            data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
            data_hora_previsao = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 01:00:00")),
            valor = c(10, 20),
            passo_prev = "D+0"
        ),
        data.table(
            id_modelo_nwp = "GFS", id_usina = "B", latitude = -26, longitude = -49,
            data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
            data_hora_previsao = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 01:00:00")),
            valor = c(30, 50),
            passo_prev = "D+0"
        )
    )
    res3 <- interpolar_30min(copy(dt3))
    expect_equal(nrow(res3), 6)
    expect_equal(res3$valor[2], 15)
    expect_equal(res3$valor[5], 40)
})


test_that("associa_nwp_usina cache", {
    dt_usinas <- gen_usinas(ids = c("USI1", "USI2"))
    irrad <- gen_irradiancia_prevista(ids = c("USI1", "USI2"))

    clear_haversine_cache()

    result1 <- associa_nwp_usina(dt_usinas, irrad)

    result2 <- associa_nwp_usina(dt_usinas, irrad)
    expect_identical(result1, result2)

    clear_haversine_cache()
    result3 <- associa_nwp_usina(dt_usinas, irrad)
    expect_identical(result1, result3)

    dt_usinas2 <- gen_usinas(ids = c("USI3"))
    result4 <- associa_nwp_usina(dt_usinas2, irrad)
    expect_true(nrow(result4) > 0)
    expect_equal(length(ls(mhpfv:::.haversine_cache)), 2L)

    clear_haversine_cache()
})


test_that("find_nearest_nwp_coords", {
    f <- find_nearest_nwp_coords
    expect_true(is.function(f))

    test_that("find_nearest_nwp_coords returns correct mapping", {
        dt_usinas <- gen_usinas(ids = c("USI1", "USI2"))
        irrad <- gen_irradiancia_prevista(ids = c("USI1", "USI2"))
        coord_prev <- unique(irrad[, .(latitude, longitude)])

        clear_haversine_cache()
        mapping <- f(dt_usinas, coord_prev)

        expect_true(is.data.table(mapping))
        expect_equal(nrow(mapping), 2L)
        expect_true(all(
            c("id_usina", "nearest_latitude", "nearest_longitude") %in%
                names(mapping)
        ))
        expect_equal(sort(mapping$id_usina), c("USI1", "USI2"))

        clear_haversine_cache()
    })
})
