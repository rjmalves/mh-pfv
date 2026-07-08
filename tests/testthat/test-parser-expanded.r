test_that("get_parser returns Parser R6 object", {
    parser <- get_parser()
    expect_true(inherits(parser, "R6"))
    expect_true(inherits(parser, "Parser"))
})

test_that("get_parser result has parse_args method", {
    parser <- get_parser()
    expect_true(is.function(parser$parse_args))
})

test_that("get_parser has --datadir argument with default ./data", {
    parser <- get_parser()
    args <- parser$parse_args(c())
    expect_true("datadir" %in% names(args))
    expect_equal(args$datadir, "./data")
})

test_that("get_parser accepts custom --datadir value", {
    parser <- get_parser()
    args <- parser$parse_args(c("--datadir", "/custom/path"))
    expect_equal(args$datadir, "/custom/path")
})

test_that("inner_parser_generic_args adds datadir argument to parser", {
    parser <- argparse::ArgumentParser(description = "test")
    result <- inner_parser_generic_args(parser)
    args <- result$parse_args(c())
    expect_true("datadir" %in% names(args))
})
