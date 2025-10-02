test_that("remove_congelados", {
    # caso trivial ------------------------------

    v1 <- rep(1, 10)
    v1_parsed <- remove_congelados(v1, 5, .01)

    expect_equal(length(v1), length(v1_parsed))
    expect_true(all(is.na(v1_parsed[-1])))

    # janelas repetidas separadas ---------------

    v2 <- c(rep(1, 6), 7, 3, 8, 9, 4, rep(1, 10))
    v2_parsed <- remove_congelados(v2, 5, .01)

    expect_equal(length(v2), length(v2_parsed))
    expect_true(all(is.na(v2_parsed[c(2:6, 13:21)])))
})

test_that("checa_valores_congelados", {
    d1 <- data.table(
        id_fonte_observacao = rep(letters[1:2], each = 10),
        data_hora_observacao = rep(as.Date("2020-01-01"), 20),
        valor = rep(1:2, each = 10)
    )

    # execucao com valores default --------------

    d1_parsed <- expect_no_error(checa_valores_congelados(d1))
})


test_that("checa_valores_congelados", {
    # Teste 1: valores totalmente congelados devem ser substituidos por NA
    d1 <- data.table(
        id_fonte_observacao = rep(letters[1:2], each = 10),
        data_hora_observacao = rep(seq.POSIXt(as.POSIXct("2020-01-01"), by = "hour", length.out = 10), 2),
        valor = rep(1, 20)
    )
    d1_parsed <- expect_no_error(checa_valores_congelados(copy(d1)))
    expect_true(all(is.na(d1_parsed$valor)))

    # Teste 2: funcao aceita multiplos pares de parametros
    d2 <- data.table(
        id_fonte_observacao = rep("A", 20),
        data_hora_observacao = seq.POSIXt(as.POSIXct("2021-01-01"), by = "hour", length.out = 20),
        valor = c(rep(10, 5), rep(20, 5), 1:10)
    )
    d2_parsed <- expect_no_error(
        checa_valores_congelados(copy(d2), v_n_valores = c(3, 5, 7), v_limiar = c(0.01, 0.01, 0.01))
    )
    expect_true(any(is.na(d2_parsed$valor)))
    expect_equal(nrow(d2_parsed), nrow(d2))

    # Teste 3: erro se tamanhos dos vetores forem diferentes
    d3 <- data.table(
        id_fonte_observacao = rep("B", 10),
        data_hora_observacao = seq.POSIXt(as.POSIXct("2021-01-01"), by = "hour", length.out = 10),
        valor = 1:10
    )
    expect_error(
        checa_valores_congelados(copy(d3), v_n_valores = c(3, 5), v_limiar = c(0.01)),
        "mesmo comprimento"
    )

    # Teste 4: valores com alta variabilidade nao devem ser alterados
    d4 <- data.table(
        id_fonte_observacao = rep("C", 10),
        data_hora_observacao = seq.POSIXt(as.POSIXct("2021-01-01"), by = "hour", length.out = 10),
        valor = seq(1, 10)
    )
    d4_parsed <- expect_no_error(checa_valores_congelados(copy(d4)))
    expect_equal(d4_parsed$valor, d4$valor)
})


test_that("manter_geracao_congelada_em_cortes", {
  # Teste 1: dados de exemplo
  geracao_usina_limpos <- data.table(
    id_usina = c("A", "A", "A"),
    data_hora_observacao = as.POSIXct(c("2025-06-28 00:00:00", "2025-06-28 00:30:00", "2025-06-28 01:00:00")),
    valor = c(10, 20, 30)
  )
  
  geracao_usina <- data.table(
    id_usina = c("A", "A", "A"),
    data_hora_observacao = as.POSIXct(c("2025-06-28 00:00:00", "2025-06-28 00:30:00", "2025-06-28 01:00:00")),
    valor = c(100, 200, 300)
  )
  
  corte_obs <- data.table(
    id_usina = c("A", "A", "A"),
    data_hora_observacao = as.POSIXct(c("2025-06-28 00:00:00", "2025-06-28 00:30:00", "2025-06-28 01:00:00")),
    valor = c(1, 0, 1)
  )
  
  # Aplicar cortes
  resultado <- manter_geracao_congelada_em_cortes(geracao_usina_limpos, geracao_usina, corte_obs)
  
  # Teste 2: valores onde corte == 1 sao atualizados
  expect_equal(resultado$valor[1], 100)
  expect_equal(resultado$valor[3], 300)
  
  # Teste 3: valores onde corte == 0 nao sao alterados
  expect_equal(resultado$valor[2], 20)
  
  # Teste 4: tamanho do data.table nao muda
  expect_equal(nrow(resultado), 3)
  
  # Teste 5: id_usina e datas nao mudam
  expect_equal(resultado$id_usina, geracao_usina_limpos$id_usina)
  expect_equal(resultado$data_hora_observacao, geracao_usina_limpos$data_hora_observacao)
})


test_that("checa_valores_overbound", {
    # Teste 1: Remove valores abaixo e acima dos limites
    dt1 <- data.table(valor = c(-10, 0, 5, 10, 100))
    res1 <- checa_valores_overbound(copy(dt1), limites = c(0, 10))
    expect_equal(res1$valor, c(NA, 0, 5, 10, NA))

    # Teste 2: Limites infinitos nao removem nada
    dt2 <- data.table(valor = c(-Inf, -100, 0, 100, Inf))
    res2 <- checa_valores_overbound(copy(dt2), limites = c(-Inf, Inf))
    expect_equal(res2$valor, dt2$valor)

    # Teste 3: Limite  restritivo remove corretamente
    dt3 <- data.table(valor = c(1, 2, 3, 4))
    res3 <- checa_valores_overbound(copy(dt3), limites = c(0, 2))
    expect_equal(res3$valor, c(1, 2, NA, NA))

    # Teste 4: Valores NA permanecem como NA
    dt6 <- data.table(valor = c(NA, 1, 2))
    res6 <- checa_valores_overbound(copy(dt6), limites = c(0, 2))
    expect_equal(res6$valor, c(NA, 1, 2))

    # Teste 6: Limite inferior maior que o superior (caso invalido)
    dt7 <- data.table(valor = c(1, 2, 3))
    res7 <- checa_valores_overbound(copy(dt7), limites = c(5, 1))
    expect_equal(res7$valor, rep(NA_real_, 3))
})



test_that("combina_fontes", {
    # Dados de exemplo
    dt_geracao <- data.table(
        id_fonte_observacao = c(rep("A", 5), rep("B", 5)),
        id_usina = rep("U1", 10),
        data_hora_observacao = rep(seq.POSIXt(as.POSIXct("2021-01-01"), by = "hour", length.out = 5), 2),
        valor = c(NA, rep(1, 4), rep(2, 4), NA)
    )

    # Testa geracao_observada
    resultado_geracao <- combina_fontes(dt_geracao, "geracao_observada", ordem = c("B", "A"))
    expect_equal(length(unique(resultado_geracao$data_hora_observacao)), nrow(resultado_geracao))

    resultado_geracao <- combina_fontes(dt_geracao, "geracao_observada", ordem = c("A", "B"))
    expect_equal(length(unique(resultado_geracao$data_hora_observacao)), nrow(resultado_geracao))
})



test_that("combina_dados", {
    # Dados base
    dt <- data.table(
        id_fonte_observacao = c("A", "B", "A", "B", "C"),
        id_usina = c("U1", "U1", "U2", "U2", "U2"),
        data_hora_observacao = as.POSIXct(c(
            "2025-01-01 00:00", "2025-01-01 00:00",
            "2025-01-01 01:00", "2025-01-01 01:00",
            "2025-01-01 01:00"
        )),
        valor = c(NA, 10, 20, NA, 30),
        status = c(NA, NA, NA, NA, NA)
    )

    ordem <- c("A", "B", "C")

    # Aplica funcao
    resultado <- combina_dados(dt, ordem)

    # Testa se resultado tem mesmas colunas e mesmo numero de linhas que combinacoes unicas
    expect_equal(names(resultado), names(dt))
    expect_equal(nrow(resultado), 2)

    # Testa se valores foram escolhidos corretamente por prioridade
    # Para U1: valor nao NA da fonte B (prioridade 2)
    # Para U2: valor nao NA da fonte A (prioridade 1) e C (prioridade 3), entao pega A
    expect_equal(resultado$id_usina, c("U1", "U2"))
    expect_equal(resultado$valor, c(10, 20))

    # Testa se campo id_fonte_observacao foi atualizado para "Consis" onde houver valor
    expect_equal(resultado$id_fonte_observacao, c("Consis", "Consis"))

    # Testa se campo status corresponde a ordem_prioridade (2 para B, 1 para A)
    expect_equal(resultado$status, c(2, 1))

    # Testa comportamento quando todos os valores sao NA
    dt2 <- data.table(
        id_fonte_observacao = c("A", "B"),
        id_usina = c("U1", "U1"),
        data_hora_observacao = as.POSIXct(c("2025-01-01 00:00", "2025-01-01 00:00")),
        valor = c(NA, NA),
        status = c(NA, NA)
    )

    resultado2 <- combina_dados(dt2, ordem)

    expect_equal(nrow(resultado2), 1)
    expect_true(is.na(resultado2$valor))
    expect_true(is.na(resultado2$status))
    expect_true(is.na(resultado2$id_fonte_observacao))
})

