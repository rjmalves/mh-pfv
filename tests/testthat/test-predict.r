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
