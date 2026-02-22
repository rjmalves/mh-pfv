test_that("read_env_flag", {
    f <- mhpfv:::read_env_flag
    expect_true(is.function(f))

    test_that("read_env_flag retorna padrao quando variavel nao esta definida", {
        withr::local_envvar(MHPFV_TEST_FLAG = NA)
        expect_false(f("MHPFV_TEST_FLAG", FALSE))
        expect_true(f("MHPFV_TEST_FLAG", TRUE))
    })

    test_that("read_env_flag retorna TRUE para 'true'", {
        withr::local_envvar(MHPFV_TEST_FLAG = "true")
        expect_true(f("MHPFV_TEST_FLAG", FALSE))
    })

    test_that("read_env_flag retorna TRUE para 'TRUE' (maiusculo)", {
        withr::local_envvar(MHPFV_TEST_FLAG = "TRUE")
        expect_true(f("MHPFV_TEST_FLAG", FALSE))
    })

    test_that("read_env_flag retorna TRUE para '1'", {
        withr::local_envvar(MHPFV_TEST_FLAG = "1")
        expect_true(f("MHPFV_TEST_FLAG", FALSE))
    })

    test_that("read_env_flag retorna TRUE para 'yes'", {
        withr::local_envvar(MHPFV_TEST_FLAG = "yes")
        expect_true(f("MHPFV_TEST_FLAG", FALSE))
    })

    test_that("read_env_flag retorna FALSE para 'false'", {
        withr::local_envvar(MHPFV_TEST_FLAG = "false")
        expect_false(f("MHPFV_TEST_FLAG", TRUE))
    })

    test_that("read_env_flag retorna FALSE para 'FALSE' (maiusculo)", {
        withr::local_envvar(MHPFV_TEST_FLAG = "FALSE")
        expect_false(f("MHPFV_TEST_FLAG", TRUE))
    })

    test_that("read_env_flag retorna FALSE para '0'", {
        withr::local_envvar(MHPFV_TEST_FLAG = "0")
        expect_false(f("MHPFV_TEST_FLAG", TRUE))
    })

    test_that("read_env_flag retorna FALSE para 'no'", {
        withr::local_envvar(MHPFV_TEST_FLAG = "no")
        expect_false(f("MHPFV_TEST_FLAG", TRUE))
    })

    test_that("read_env_flag retorna padrao para valor invalido", {
        withr::local_envvar(MHPFV_TEST_FLAG = "banana")
        expect_false(f("MHPFV_TEST_FLAG", FALSE))
        expect_true(f("MHPFV_TEST_FLAG", TRUE))
    })

    test_that("read_env_flag ignora espacos em branco ao redor do valor", {
        withr::local_envvar(MHPFV_TEST_FLAG = "  true  ")
        expect_true(f("MHPFV_TEST_FLAG", FALSE))
    })
})

test_that("read_env_integer", {
    f <- mhpfv:::read_env_integer
    expect_true(is.function(f))

    test_that("read_env_integer retorna NULL quando variavel nao esta definida", {
        withr::local_envvar(MHPFV_TEST_INT = NA)
        expect_null(f("MHPFV_TEST_INT"))
    })

    test_that("read_env_integer retorna padrao customizado quando nao definida", {
        withr::local_envvar(MHPFV_TEST_INT = NA)
        expect_equal(f("MHPFV_TEST_INT", default = 4L), 4L)
    })

    test_that("read_env_integer retorna inteiro correto para valor valido", {
        withr::local_envvar(MHPFV_TEST_INT = "4")
        expect_equal(f("MHPFV_TEST_INT"), 4L)
    })

    test_that("read_env_integer retorna inteiro correto para '1'", {
        withr::local_envvar(MHPFV_TEST_INT = "1")
        expect_equal(f("MHPFV_TEST_INT"), 1L)
    })

    test_that("read_env_integer retorna NULL para valor nao numerico", {
        withr::local_envvar(MHPFV_TEST_INT = "abc")
        expect_null(f("MHPFV_TEST_INT"))
    })

    test_that("read_env_integer retorna NULL para valor negativo", {
        withr::local_envvar(MHPFV_TEST_INT = "-1")
        expect_null(f("MHPFV_TEST_INT"))
    })

    test_that("read_env_integer retorna NULL para zero", {
        withr::local_envvar(MHPFV_TEST_INT = "0")
        expect_null(f("MHPFV_TEST_INT"))
    })

    test_that("read_env_integer retorna integer (nao double)", {
        withr::local_envvar(MHPFV_TEST_INT = "3")
        result <- f("MHPFV_TEST_INT")
        expect_true(is.integer(result))
    })
})

test_that("cli_main", {
    f <- cli_main
    expect_true(is.function(f))

    test_that("cli_main levanta erro com datadir invalido", {
        expect_error(f(datadir = "/nonexistent/path"))
    })

    test_that("cli_main tem backward compatibility com apenas datadir", {
        skip_if_not(dir.exists(test_path("data")))
        conn <- conectamock_pfv(test_path("data"))
        config <- get_config(conn)
        parsed <- parse_config(config, conn)
        expect_true(parsed$mode %in% c("train", "predict"))
    })

    test_that("cli_main levanta erro com modo invalido", {
        skip_if_not(dir.exists(test_path("data")))

        tmp_data <- withr::local_tempdir()
        src_files <- list.files(test_path("data"), full.names = TRUE)
        file.copy(src_files, tmp_data)

        config_path <- file.path(tmp_data, "config.jsonc")
        config_text <- readLines(config_path, warn = FALSE)
        config_text <- gsub('"train"', '"invalid_mode"', config_text)
        writeLines(config_text, config_path)

        expect_error(f(datadir = tmp_data), "Modo invalido")
    })

    test_that("cli_main usa MHPFV_PARALLEL quando parallel nao e TRUE", {
        withr::local_envvar(MHPFV_PARALLEL = "true", MHPFV_RESUME = NA)
        parallel_recebido <- NULL
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(config, parallel = FALSE, resume = FALSE, ...) {
                parallel_recebido <<- parallel
            },
            .package = "mhpfv"
        )
        f(datadir = "./data")
        expect_true(parallel_recebido)
    })

    test_that("cli_main usa MHPFV_RESUME quando resume nao e TRUE", {
        withr::local_envvar(MHPFV_PARALLEL = NA, MHPFV_RESUME = "true")
        resume_recebido <- NULL
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(config, parallel = FALSE, resume = FALSE, ...) {
                resume_recebido <<- resume
            },
            .package = "mhpfv"
        )
        f(datadir = "./data")
        expect_true(resume_recebido)
    })

    test_that("cli_main com parallel=TRUE sobrepoe MHPFV_PARALLEL=false", {
        withr::local_envvar(MHPFV_PARALLEL = "false")
        parallel_recebido <- NULL
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(config, parallel = FALSE, resume = FALSE, ...) {
                parallel_recebido <<- parallel
            },
            .package = "mhpfv"
        )
        f(datadir = "./data", parallel = TRUE)
        expect_true(parallel_recebido)
    })

    test_that("cli_main descarta workers quando parallel e FALSE", {
        withr::local_envvar(MHPFV_PARALLEL = NA, MHPFV_RESUME = NA)
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(config, parallel = FALSE, resume = FALSE, ...) invisible(NULL),
            .package = "mhpfv"
        )
        expect_no_error(f(datadir = "./data", parallel = FALSE, workers = 4L))
    })

    test_that("cli_main define MHPFV_WORKERS quando parallel=TRUE e workers e fornecido", {
        withr::local_envvar(MHPFV_PARALLEL = NA, MHPFV_RESUME = NA, MHPFV_WORKERS = NA)
        workers_env_capturado <- NULL
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(config, parallel = FALSE, resume = FALSE, ...) {
                workers_env_capturado <<- Sys.getenv("MHPFV_WORKERS", unset = "")
            },
            .package = "mhpfv"
        )
        f(datadir = "./data", parallel = TRUE, workers = 4L)
        expect_equal(workers_env_capturado, "4")
    })

    test_that("cli_main nao define MHPFV_WORKERS quando workers e NULL", {
        withr::local_envvar(MHPFV_PARALLEL = NA, MHPFV_RESUME = NA, MHPFV_WORKERS = NA)
        workers_env_capturado <- NULL
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(config, parallel = FALSE, resume = FALSE, ...) {
                workers_env_capturado <<- Sys.getenv("MHPFV_WORKERS", unset = "UNSET")
            },
            .package = "mhpfv"
        )
        f(datadir = "./data", parallel = TRUE, workers = NULL)
        expect_equal(workers_env_capturado, "UNSET")
    })

    test_that("cli_main passa parallel e resume para predict_main", {
        withr::local_envvar(MHPFV_PARALLEL = NA, MHPFV_RESUME = NA)
        parallel_recebido <- NULL
        resume_recebido <- NULL
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "predict"),
            predict_main = function(config, parallel = FALSE, resume = FALSE, ...) {
                parallel_recebido <<- parallel
                resume_recebido <<- resume
            },
            .package = "mhpfv"
        )
        f(datadir = "./data", parallel = TRUE, resume = TRUE)
        expect_true(parallel_recebido)
        expect_true(resume_recebido)
    })

    test_that("cli_main retorna 0L invisivel em sucesso", {
        withr::local_envvar(MHPFV_PARALLEL = NA, MHPFV_RESUME = NA)
        local_mocked_bindings(
            conectamock_pfv = function(...) list(),
            get_config = function(...) list(),
            parse_config = function(...) list(mode = "train"),
            train_main = function(...) invisible(NULL),
            .package = "mhpfv"
        )
        result <- withVisible(f(datadir = "./data"))
        expect_equal(result$value, 0L)
        expect_false(result$visible)
    })
})

test_that("get_parser com novos argumentos", {
    f <- get_parser
    expect_true(is.function(f))

    test_that("get_parser inclui --parallel com default FALSE", {
        parser <- f()
        args <- parser$parse_args(c())
        expect_true("parallel" %in% names(args))
        expect_false(args$parallel)
    })

    test_that("get_parser aceita --parallel e retorna TRUE", {
        parser <- f()
        args <- parser$parse_args(c("--parallel"))
        expect_true(args$parallel)
    })

    test_that("get_parser inclui --resume com default FALSE", {
        parser <- f()
        args <- parser$parse_args(c())
        expect_true("resume" %in% names(args))
        expect_false(args$resume)
    })

    test_that("get_parser aceita --resume e retorna TRUE", {
        parser <- f()
        args <- parser$parse_args(c("--resume"))
        expect_true(args$resume)
    })

    test_that("get_parser inclui --workers com default NULL", {
        parser <- f()
        args <- parser$parse_args(c())
        expect_true("workers" %in% names(args))
        expect_null(args$workers)
    })

    test_that("get_parser aceita --workers com valor inteiro", {
        parser <- f()
        args <- parser$parse_args(c("--workers", "4"))
        expect_equal(args$workers, 4L)
    })

    test_that("get_parser preserva --datadir com default ./data", {
        parser <- f()
        args <- parser$parse_args(c())
        expect_equal(args$datadir, "./data")
    })
})

test_that("setup_parallel_plan com MHPFV_WORKERS", {
    f <- setup_parallel_plan
    expect_true(is.function(f))

    test_that("setup_parallel_plan usa MHPFV_WORKERS quando workers e NULL", {
        withr::local_envvar(MHPFV_WORKERS = "2")
        withr::defer(future::plan("sequential"))
        f(workers = NULL, strategy = "multisession")
        cfg <- get_parallel_config()
        expect_equal(cfg$workers, 2L)
    })

    test_that("setup_parallel_plan ignora MHPFV_WORKERS quando workers e fornecido", {
        withr::local_envvar(MHPFV_WORKERS = "8")
        withr::defer(future::plan("sequential"))
        f(workers = 2L, strategy = "multisession")
        cfg <- get_parallel_config()
        expect_equal(cfg$workers, 2L)
    })

    test_that("setup_parallel_plan usa auto-detect quando MHPFV_WORKERS e invalido", {
        withr::local_envvar(MHPFV_WORKERS = "banana")
        withr::defer(future::plan("sequential"))
        expect_no_error(f(workers = NULL, strategy = "multisession"))
        cfg <- get_parallel_config()
        expect_gte(cfg$workers, 1L)
    })

    test_that("setup_parallel_plan usa auto-detect quando MHPFV_WORKERS e negativo", {
        withr::local_envvar(MHPFV_WORKERS = "-1")
        withr::defer(future::plan("sequential"))
        expect_no_error(f(workers = NULL, strategy = "multisession"))
        cfg <- get_parallel_config()
        expect_gte(cfg$workers, 1L)
    })

    test_that("setup_parallel_plan usa auto-detect quando MHPFV_WORKERS e zero", {
        withr::local_envvar(MHPFV_WORKERS = "0")
        withr::defer(future::plan("sequential"))
        expect_no_error(f(workers = NULL, strategy = "multisession"))
        cfg <- get_parallel_config()
        expect_gte(cfg$workers, 1L)
    })

    test_that("setup_parallel_plan nao usa MHPFV_WORKERS quando string vazia", {
        withr::local_envvar(MHPFV_WORKERS = "")
        withr::defer(future::plan("sequential"))
        expect_no_error(f(workers = NULL, strategy = "multisession"))
        cfg <- get_parallel_config()
        expect_gte(cfg$workers, 1L)
    })
})
