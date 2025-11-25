test_that("checa_valores_faltantes", {
    # Teste 1: Conversao para data.table se necessario
    df <- data.frame(
        id_fonte_observacao = c("A", "A"),
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(10, 20),
        id_usina = c(1, 1)
    )
    res <- checa_valores_faltantes(df)
    expect_s3_class(res, "data.table")

    # Teste 2: Substituicao de valores "NaN" por NA
    dt2 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(NaN, 5),
        id_usina = 1
    )
    res2 <- checa_valores_faltantes(dt2)
    expect_true(is.na(res2$valor[1]))
    expect_equal(res2$valor[2], 5)

    # Teste 3: Substituicao de valores 999 por NA
    dt3 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
        valor = c(999, 1),
        id_usina = 1
    )
    res3 <- checa_valores_faltantes(dt3)
    expect_true(is.na(res3$valor[1]))
    expect_equal(res3$valor[2], 1)

    # Teste 4: Preenchimento da sequencia de tempo de 30 em 30 minutos
    dt4 <- data.table(
        id_fonte_observacao = "A",
        data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 01:00:00")),
        valor = c(1, 2),
        id_usina = 1
    )
    res4 <- checa_valores_faltantes(dt4)
    expect_equal(nrow(res4), 3) # 00:00, 00:30, 01:00
    expect_true(is.na(res4$valor[2])) # valor preenchido com NA

    # Teste 5: Replicacao de id_usina unico
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
    # Teste 1: Verifica se a funcao retorna data.table
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

    # Teste 2: Verifica sobreposicao de valores e status de dt2
    expect_equal(res$valor[res$data_hora_observacao == as.POSIXct("2020-01-01 00:30:00")], 25)
    expect_equal(res$status[res$data_hora_observacao == as.POSIXct("2020-01-01 00:30:00")], 2)

    # Teste 3: Verifica que valores de dt1 permanecem onde dt2 nao tem dados
    expect_equal(res$valor[res$data_hora_observacao == as.POSIXct("2020-01-01 00:00:00")], 10)
    expect_equal(res$status[res$data_hora_observacao == as.POSIXct("2020-01-01 00:00:00")], 1)

    # Teste 4: Verifica coluna id_fonte_observacao
    expect_true(all(res$id_fonte_observacao == "Consis"))

    # Teste 5: Verifica ordenacao por id_usina e data_hora_observacao
    expect_equal(res$id_usina, sort(res$id_usina))
    expect_equal(res$data_hora_observacao, sort(res$data_hora_observacao))

    # Teste 6: Verifica combinacao com multiplas usinas
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
    # Dados de entrada
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

    # Teste 1: associa_nwp_usina retorna data.table
    res1 <- associa_nwp_usina(dt_usinas, dt_irrad_prev)
    expect_s3_class(res1, "data.table")

    # Teste 2: cada usina recebe coordenada mais proxima
    usina1_coord <- res1[id_usina == 1, .(latitude, longitude)]
    usina2_coord <- res1[id_usina == 2, .(latitude, longitude)]
    expect_true(all(usina1_coord$latitude == -20))
    expect_true(all(usina1_coord$longitude == -45))
    expect_true(all(usina2_coord$latitude == -19.9))
    expect_true(all(usina2_coord$longitude == -44.9))

    # Teste 3: adicionar coluna id_usina
    expect_true("id_usina" %in% names(res1))

    # Teste 4: adicionar_passo_previsao calcula passo corretamente
    res2 <- adicionar_passo_previsao(res1)
    expect_true("passo_prev" %in% names(res2))
    expect_equal(res2$passo_prev[1], "D+1") # 03-10 minus 02-10

    # Teste 5: passo_prev numerico correto para todas as linhas
    dif_dias <- as.integer(as.Date(res2$data_hora_previsao) - as.Date(res2$data_hora_rodada))
    expect_equal(as.integer(sub("D+", "", res2$passo_prev)), dif_dias)

    # Teste 6: colunas originais preservadas
    expect_true(all(c(
        "id_modelo_nwp", "latitude", "longitude", "data_hora_previsao",
        "data_hora_rodada", "irradiancia"
    ) %in% names(res2)))
})


test_that("adicionar_passo_previsao", {
    # Teste 1: passo_prev deve ser D+0 quando previsao e rodada sao no mesmo dia
    dt1 <- data.table(
        data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
        data_hora_previsao = as.POSIXct("2025-08-03 12:00:00")
    )
    res1 <- adicionar_passo_previsao(copy(dt1))
    expect_equal(res1$passo_prev, "D+0")

    # Teste 2: passo_prev deve ser D+1 quando previsao e 1 dia apos a rodada
    dt2 <- data.table(
        data_hora_rodada = as.POSIXct("2025-08-03 00:00:00"),
        data_hora_previsao = as.POSIXct("2025-08-04 00:00:00")
    )
    res2 <- adicionar_passo_previsao(copy(dt2))
    expect_equal(res2$passo_prev, "D+1")

    # Teste 3: deve funcionar para multiplas linhas com diferentes dias
    dt3 <- data.table(
        data_hora_rodada = as.POSIXct(c("2025-08-03 00:00:00", "2025-08-03 00:00:00", "2025-08-03 00:00:00")),
        data_hora_previsao = as.POSIXct(c("2025-08-03 03:00:00", "2025-08-04 03:00:00", "2025-08-05 03:00:00"))
    )
    res3 <- adicionar_passo_previsao(copy(dt3))
    expect_equal(res3$passo_prev, c("D+0", "D+1", "D+2"))

    # Teste 4: deve converter corretamente colunas que nao estao em POSIXct
    dt4 <- data.table(
        data_hora_rodada = c("2025-08-03 00:00:00"),
        data_hora_previsao = c("2025-08-05 00:00:00")
    )
    res4 <- adicionar_passo_previsao(copy(dt4))
    expect_equal(res4$passo_prev, "D+2")

    # Teste 5: deve retornar as mesmas colunas da entrada mais passo_prev
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
    # Teste 1: verifica se a funcao retorna data.table
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

    # Teste 2: verifica se a interpolacao cria ponto intermediario a cada 30 min
    expect_equal(nrow(res1), 3) # 2 horas -> 1 intervalo -> 3 linhas

    # Teste 3: verifica se os valores interpolados estao corretos
    expect_equal(res1$valor[2], 15) # ponto intermediario entre 10 e 20

    # Teste 4: verifica se as colunas permanecem na mesma ordem do original
    expect_equal(names(res1), names(dt1))

    # Teste 5: verifica se multipla linhas por grupo sao interpoladas corretamente
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
    expect_equal(nrow(res2), 5) # 3 horas -> 2 intervalos -> 5 linhas
    expect_equal(res2$valor[2], 15) # primeiro ponto intermediario
    expect_equal(res2$valor[4], 25) # segundo ponto intermediario

    # Teste 6: verifica se funcao funciona com multiplos grupos
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
    expect_equal(nrow(res3), 6) # 2 grupos -> 3 linhas cada
    expect_equal(res3$valor[2], 15) # grupo A
    expect_equal(res3$valor[5], 40) # grupo B
})
