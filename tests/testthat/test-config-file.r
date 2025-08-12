gen_config <- function() {
    list(
        mode = "predict",
        input = "./data",
        output = "./out",
        artifact = ".",
        janela = 90,
        ids_usinas = list(),
        ordem_prioridade_fontes = list("PI", "CCEE", "CCEE1h"),
        ordem_prioridade_modelosNWP = list("GFS"),
        fator_tolerancia_limite_superior_geracao = 1.1
    )
}

test_that("valida_nomes_config", {
    conf <- gen_config()

    # padrao
    expect_null(valida_nomes_config(conf))

    # elemento extra
    conf$nome_extra <- "erro"
    expect_null(valida_nomes_config(conf))

    # elemento faltante
    conf$input <- NULL
    expect_error(valida_nomes_config(conf))
})

test_that("valid_tipos_unit", {

    # tipos escalares

    x <- "a"
    tipos <- "character"
    expect_true(valid_tipos_unit(x, tipos))

    tipos <- list("character")
    expect_true(valid_tipos_unit(x, tipos))

    tipos <- list("character", "numeric")
    expect_true(valid_tipos_unit(x, tipos))

    x <- 10
    tipos <- list("character", "numeric")
    expect_true(valid_tipos_unit(x, tipos))

    x <- 10L
    tipos <- list("character", "numeric", "integer")
    expect_true(valid_tipos_unit(x, tipos))

    x <- 10L
    tipos <- list("character", "numeric", "integer")
    expect_true(valid_tipos_unit(x, tipos))

    x <- NULL
    tipos <- list("character")
    expect_false(valid_tipos_unit(x, tipos))

    # tipos lista

    tipos <- list("character", "numeric")
    expect_false(valid_tipos_unit(x, tipos))
})

test_that("valid_tipos", {

    l <- list(1, 2, 3)
    tipos <- "numeric"
    expect_true(valid_tipos(l, tipos))

    tipos <- list("numeric", "integer")
    expect_true(valid_tipos(l, tipos))

    tipos <- list("Date")
    expect_false(valid_tipos(l, tipos))

    # qualquer coisa deveria funcionar aqui
    l <- list()
    tipos <- list("numeric", "Date", "character", "integer")
    expect_true(valid_tipos(l, tipos))
})

test_that("valida_tipos_config", {
    conf <- gen_config()

    # padrao

    # elemento extra
    conf$extra <- NA_integer_
    expect_null(valida_tipos_config(conf))

    # elemento errado
    conf$input <- NA_integer_
    expect_error(valida_tipos_config(conf))

    # data string
    conf <- gen_config()
    conf$janela <- c("2021-01-01", "2021-04-01")
    expect_null(valida_tipos_config(conf))
})

test_that("parsearg_janela", {
    janela <- c("2021-01-01", "2021-02-01")
    parsed <- parsearg_janela(janela)
    expect_true(inherits(parsed, "Date"))
    expect_true(parsed[1] == as.Date("2021-01-01"))
    expect_true(parsed[2] == as.Date("2021-02-01"))

    janela <- 10
    parsed <- parsearg_janela(janela)
    expect_true(inherits(parsed, "Date"))
    expect_true(parsed[1] == Sys.Date() - janela - 1)
    expect_true(parsed[2] == Sys.Date() - 1)
})
