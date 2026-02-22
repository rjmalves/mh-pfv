test_that("logger_setup", {
    f <- logger_setup
    expect_true(is.function(f))

    test_that("logger_setup retorna objeto Logger", {
        lg <- f()
        expect_true(inherits(lg, "Logger"))
    })

    test_that("logger_setup retorna o logger mhpfv nao o root", {
        lg <- f()
        expect_equal(lg$name, "mhpfv")
    })

    test_that("logger_setup desativa propagacao para o root", {
        lg <- f()
        expect_false(lg$propagate)
    })

    test_that("logger_setup usa threshold info por padrao", {
        withr::local_envvar(LOG_LEVEL = NA)
        lg <- f()
        expect_equal(lg$threshold, 400L)
    })

    test_that("logger_setup respeita LOG_LEVEL=debug", {
        withr::local_envvar(LOG_LEVEL = "debug")
        lg <- f()
        expect_equal(lg$threshold, 500L)
    })

    test_that("logger_setup respeita LOG_LEVEL=warn", {
        withr::local_envvar(LOG_LEVEL = "warn")
        lg <- f()
        expect_equal(lg$threshold, 300L)
    })

    test_that("logger_setup configura appender console nomeado no logger mhpfv", {
        lg <- f()
        expect_true("console" %in% names(lg$appenders))
    })

    test_that("logger_setup configura layout LayoutFormat por padrao", {
        withr::local_envvar(MHPFV_LOG_FORMAT = NA)
        lg <- f()
        layout <- lg$appenders$console$layout
        expect_true(inherits(layout, "LayoutFormat"))
    })

    test_that("logger_setup configura layout LayoutJson no logger mhpfv quando MHPFV_LOG_FORMAT=json", {
        mhpfv_lg <- lgr::get_logger("mhpfv")
        original_layout <- mhpfv_lg$appenders$console$layout
        withr::defer(mhpfv_lg$appenders$console$set_layout(original_layout))

        withr::local_envvar(MHPFV_LOG_FORMAT = "json")
        f()
        expect_true(inherits(mhpfv_lg$appenders$console$layout, "LayoutJson"))
    })
})

test_that("get_pkg_logger", {
    f <- get_pkg_logger
    expect_true(is.function(f))

    test_that("get_pkg_logger retorna objeto Logger", {
        lg <- f()
        expect_true(inherits(lg, "Logger"))
    })

    test_that("get_pkg_logger retorna o mesmo objeto do namespace", {
        lg <- f()
        ns_lg <- get("lg", envir = asNamespace("mhpfv"))
        expect_identical(lg, ns_lg)
    })
})

test_that("set_log_context", {
    f <- mhpfv:::set_log_context
    expect_true(is.function(f))

    test_that("set_log_context define run_id e mode no logger", {
        withr::defer(mhpfv:::clear_log_context())
        f(run_id = "test-run-001", mode = "train")
        lg <- lgr::get_logger("mhpfv")
        fi <- lg$filters$mhpfv_ctx
        expect_false(is.null(fi))
        expect_equal(fi$values$run_id, "test-run-001")
        expect_equal(fi$values$mode, "train")
    })

    test_that("set_log_context define stage quando fornecido", {
        withr::defer(mhpfv:::clear_log_context())
        f(run_id = "test-run-002", mode = "predict", stage = "fitting")
        lg <- lgr::get_logger("mhpfv")
        fi <- lg$filters$mhpfv_ctx
        expect_equal(fi$values$stage, "fitting")
    })

    test_that("set_log_context nao define stage quando NULL", {
        withr::defer(mhpfv:::clear_log_context())
        f(run_id = "test-run-003", mode = "train", stage = NULL)
        lg <- lgr::get_logger("mhpfv")
        fi <- lg$filters$mhpfv_ctx
        expect_false("stage" %in% names(fi$values))
    })

    test_that("set_log_context substitui filtro existente", {
        withr::defer(mhpfv:::clear_log_context())
        f(run_id = "first-run", mode = "train")
        f(run_id = "second-run", mode = "predict")
        lg <- lgr::get_logger("mhpfv")
        fi <- lg$filters$mhpfv_ctx
        expect_equal(fi$values$run_id, "second-run")
        expect_equal(fi$values$mode, "predict")
        expect_equal(sum(names(lg$filters) == "mhpfv_ctx"), 1L)
    })

    test_that("set_log_context retorna NULL invisivelmente", {
        withr::defer(mhpfv:::clear_log_context())
        result <- withVisible(f(run_id = "test-run-004", mode = "train"))
        expect_null(result$value)
        expect_false(result$visible)
    })
})

test_that("clear_log_context", {
    f <- mhpfv:::clear_log_context
    expect_true(is.function(f))

    test_that("clear_log_context remove filtro de contexto apos set_log_context", {
        mhpfv:::set_log_context(run_id = "test-run-005", mode = "train")
        f()
        lg <- lgr::get_logger("mhpfv")
        expect_false("mhpfv_ctx" %in% names(lg$filters))
    })

    test_that("clear_log_context e no-op quando nenhum contexto esta definido", {
        lg <- lgr::get_logger("mhpfv")
        if ("mhpfv_ctx" %in% names(lg$filters)) lg$remove_filter("mhpfv_ctx")
        expect_no_error(f())
    })

    test_that("clear_log_context retorna NULL invisivelmente", {
        result <- withVisible(f())
        expect_null(result$value)
        expect_false(result$visible)
    })
})

test_that("configure_json_logging", {
    f <- mhpfv:::configure_json_logging
    expect_true(is.function(f))

    test_that("configure_json_logging muda layout para LayoutJson com MHPFV_LOG_FORMAT=json", {
        withr::local_envvar(MHPFV_LOG_FORMAT = "json")
        root <- lgr::get_logger()
        original_layout <- root$appenders$console$layout
        withr::defer(root$appenders$console$set_layout(original_layout))

        f(root)
        expect_true(inherits(root$appenders$console$layout, "LayoutJson"))
    })

    test_that("configure_json_logging mantem LayoutFormat sem MHPFV_LOG_FORMAT", {
        withr::local_envvar(MHPFV_LOG_FORMAT = NA)
        root <- lgr::get_logger()
        f(root)
        expect_true(inherits(root$appenders$console$layout, "LayoutFormat"))
    })

    test_that("configure_json_logging mantem LayoutFormat com valor diferente de json", {
        withr::local_envvar(MHPFV_LOG_FORMAT = "text")
        root <- lgr::get_logger()
        f(root)
        expect_true(inherits(root$appenders$console$layout, "LayoutFormat"))
    })

    test_that("configure_json_logging e case-insensitive para JSON", {
        withr::local_envvar(MHPFV_LOG_FORMAT = "JSON")
        root <- lgr::get_logger()
        original_layout <- root$appenders$console$layout
        withr::defer(root$appenders$console$set_layout(original_layout))

        f(root)
        expect_true(inherits(root$appenders$console$layout, "LayoutJson"))
    })

    test_that("configure_json_logging retorna NULL invisivelmente", {
        withr::local_envvar(MHPFV_LOG_FORMAT = NA)
        root <- lgr::get_logger()
        result <- withVisible(f(root))
        expect_null(result$value)
        expect_false(result$visible)
    })
})
