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
    id_usina = c(1,1),
    data_hora_observacao = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 00:30:00")),
    valor = c(10, 20),
    status = c(1,1)
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
    id_usina = c(1,2),
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
    data_hora_previsao = as.POSIXct(c("2025-10-03 00:00:00",
                                      "2025-10-03 00:30:00",
                                      "2025-10-03 01:00:00")),
    data_hora_rodada = as.POSIXct(c("2025-10-02 12:00:00",
                                    "2025-10-02 12:00:00",
                                    "2025-10-02 12:00:00")),
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
  expect_true(all(c("id_modelo_nwp", "latitude", "longitude", "data_hora_previsao",
                    "data_hora_rodada", "irradiancia") %in% names(res2)))

})
