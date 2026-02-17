test_that("logger_setup returns Logger object", {
    lg <- logger_setup()
    expect_true(inherits(lg, "Logger"))
})

test_that("logger_setup defaults to info threshold", {
    withr::local_envvar(LOG_LEVEL = NA)
    lg <- logger_setup()
    expect_equal(lg$threshold, 400L)
})

test_that("logger_setup respects LOG_LEVEL env var for debug", {
    withr::local_envvar(LOG_LEVEL = "debug")
    lg <- logger_setup()
    expect_equal(lg$threshold, 500L)
})

test_that("logger_setup respects LOG_LEVEL env var for warn", {
    withr::local_envvar(LOG_LEVEL = "warn")
    lg <- logger_setup()
    expect_equal(lg$threshold, 300L)
})

test_that("logger_setup configures console appender layout", {
    lg <- logger_setup()
    layout <- lg$appenders$console$layout
    expect_true(inherits(layout, "LayoutFormat"))
})

test_that("get_pkg_logger returns Logger object", {
    lg <- get_pkg_logger()
    expect_true(inherits(lg, "Logger"))
})

test_that("get_pkg_logger returns same object as namespace logger", {
    lg <- get_pkg_logger()
    ns_lg <- get("lg", envir = asNamespace("mhpfv"))
    expect_identical(lg, ns_lg)
})
