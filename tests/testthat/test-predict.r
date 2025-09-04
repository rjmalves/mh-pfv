test_that("organiza_resultados", {
    # Dados de entrada simulados
    resultados <- list(
        list(
            com_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 00:00"),
                valor = 10
            ),
            sem_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 00:00"),
                valor = 12
            )
        ),
        list(
            com_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 01:00"),
                valor = 20
            ),
            sem_cortes = data.table(
                data_hora_observacao = as.POSIXct("2025-01-01 01:00"),
                valor = 22
            )
        )
    )

    v_usinas <- c("U1", "U2")

    # Aplica a funcao
    resultado <- organiza_resultados(resultados, v_usinas)

    # Verifica se a lista de saida tem os nomes corretos
    expect_named(resultado, c("com_cortes", "sem_cortes"))

    # Verifica se as colunas existem e se id_usina foi corretamente adicionado
    expect_true(all(c("data_hora_observacao", "valor", "id_usina") %in% names(resultado$com_cortes)))
    expect_true(all(c("data_hora_observacao", "valor", "id_usina") %in% names(resultado$sem_cortes)))

    # Verifica o numero total de linhas e correspondencia de usinas
    expect_equal(nrow(resultado$com_cortes), 2)
    expect_equal(nrow(resultado$sem_cortes), 2)
    expect_equal(sort(resultado$com_cortes$id_usina), sort(v_usinas))
    expect_equal(sort(resultado$sem_cortes$id_usina), sort(v_usinas))

    # Verifica se os valores estao corretos por usina
    expect_equal(resultado$com_cortes[order(id_usina)]$valor, c(10, 20))
    expect_equal(resultado$sem_cortes[order(id_usina)]$valor, c(12, 22))

    # Testa comportamento com lista vazia
    resultado_vazio <- organiza_resultados(list(), character())
    expect_true(is.data.table(resultado_vazio$com_cortes))
    expect_true(is.data.table(resultado_vazio$sem_cortes))
    expect_equal(nrow(resultado_vazio$com_cortes), 0)
    expect_equal(nrow(resultado_vazio$sem_cortes), 0)
})


test_that("adequa_dados", {
    # Preparacao de dados
    horas_obs <- seq.POSIXt(as.POSIXct("2025-05-26 00:00"), by = "1 hour", length.out = 3)
    horas_prev <- seq.POSIXt(as.POSIXct("2025-05-26 00:00"), by = "1 hour", length.out = 2)

    obs <- data.table(
        id_usina = c("U1", "U2", "U1"),
        id_fonte_observacao = c("F1", "F2", "F1"),
        data_hora_observacao = horas_obs,
        valor = c(10, 20, 30)
    )

    prev <- data.table(
        id_modelo_nwp = c("M1", "M2"),
        data_hora_previsao = horas_prev,
        valor = c(100, 200)
    )

    resultados_leitura <- list(
        ger_obs = copy(obs),
        dcorte_obs = copy(obs),
        mhg = copy(obs),
        mhg_sem_cortes = copy(obs),
        irrad_prev = copy(prev)
    )

    v_usinas <- "U1"
    fonte <- "F1"
    modelo_nwp <- "M1"
    data_inicio <- "2025-05-26"
    data_fim <- "2025-05-26 01:00:00"

    # Teste 1: adequa_dados filtra observados corretamente
    resultados_filtrados <- adequa_dados(
        resultados_leitura,
        v_usinas,
        fonte,
        modelo_nwp,
        data_inicio,
        data_fim
    )

    obs_names <- c("ger_obs", "dcorte_obs")
    for (nm in obs_names) {
        dt <- resultados_filtrados[[nm]]
        expect_true(all(dt$id_usina %in% v_usinas))
        expect_true(all(dt$id_fonte_observacao %in% fonte))
        expect_true(all(dt$data_hora_observacao >= as.POSIXct(data_inicio) &
            dt$data_hora_observacao <= as.POSIXct(data_fim)))
    }

    # Teste 2: adequa_dados preserva elementos que nao precisam de filtro
    manter_names <- c("mhg", "mhg_sem_cortes")
    for (nm in manter_names) {
        dt <- resultados_filtrados[[nm]]
        expect_equal(nrow(dt), nrow(resultados_leitura[[nm]])) # deve permanecer igual
    }

    # Teste 3: adequa_dados filtra previstos corretamente
    prev_names <- c("irrad_prev")
    for (nm in prev_names) {
        dt <- resultados_filtrados[[nm]]
        expect_true(all(dt$id_modelo_nwp %in% modelo_nwp))
        expect_true(all(dt$data_hora_previsao >= as.POSIXct(data_inicio) &
            dt$data_hora_previsao <= as.POSIXct(data_fim)))
    }
})
