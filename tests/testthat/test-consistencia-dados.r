
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