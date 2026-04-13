test_that("valida_nomes_config", {
    conf <- gen_config("predict")
    expect_null(valida_nomes_config(conf))

    conf$nome_extra <- "erro"
    expect_null(valida_nomes_config(conf))

    conf$input <- NULL
    expect_error(valida_nomes_config(conf))
})

test_that("valid_tipos_unit", {
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

    x <- NULL
    tipos <- list("character")
    expect_false(valid_tipos_unit(x, tipos))

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

    l <- list()
    tipos <- list("numeric", "Date", "character", "integer")
    expect_true(valid_tipos(l, tipos))
})

test_that("valida_tipos_config", {
    conf <- gen_config("predict")

    conf$extra <- NA_integer_
    expect_null(valida_tipos_config(conf))

    conf$input <- NA_integer_
    expect_error(valida_tipos_config(conf))

    conf <- gen_config("predict")
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

test_that("parsearg_ids_usinas", {
    conn <- conectamock_pfv(testthat::test_path("data"))

    ids <- list("teste1", "teste2", "teste2")
    ids_parsed <- parsearg_ids_usinas(ids, conn)
    expect_identical(unique(unlist(ids)), ids_parsed)

    ref <- get_usinas(conn)$id_usina
    ids <- list()
    ids_parsed <- parsearg_ids_usinas(ids, conn)
    expect_identical(ref, ids_parsed)
})
