test_that("setup_parallel_plan", {
    f <- setup_parallel_plan
    expect_true(is.function(f))

    test_that("setup_parallel_plan com defaults configura plano valido", {
        withr::defer(future::plan("sequential"))
        f()
        cfg <- get_parallel_config()
        expect_true(cfg$workers >= 1L)
    })

    test_that("setup_parallel_plan com sequential configura plano sequential", {
        withr::defer(future::plan("sequential"))
        f(strategy = "sequential")
        cfg <- get_parallel_config()
        expect_equal(cfg$strategy, "sequential")
    })

    test_that("setup_parallel_plan respeita argumento workers", {
        withr::defer(future::plan("sequential"))
        f(workers = 2L)
        cfg <- get_parallel_config()
        expect_equal(cfg$workers, 2L)
    })

    test_that("setup_parallel_plan retorna plano anterior", {
        withr::defer(future::plan("sequential"))
        future::plan("sequential")
        old <- f(workers = 2L)
        expect_true(!is.null(old))
    })

    test_that("setup_parallel_plan com workers negativos levanta erro", {
        expect_error(f(workers = -1L), "inteiro positivo")
    })

    test_that("setup_parallel_plan com workers zero levanta erro", {
        expect_error(f(workers = 0L), "inteiro positivo")
    })

    test_that("setup_parallel_plan com strategy invalida levanta erro", {
        expect_error(f(strategy = "bad"), "arg")
    })

    test_that("setup_parallel_plan workers default e pelo menos 1", {
        withr::defer(future::plan("sequential"))
        f()
        cfg <- get_parallel_config()
        expect_gte(cfg$workers, 1L)
    })

    test_that("setup_parallel_plan com workers fracionarios levanta erro", {
        expect_error(f(workers = 2.5), "inteiro positivo")
    })

    test_that("setup_parallel_plan com workers NA levanta erro", {
        expect_error(f(workers = NA_integer_), "inteiro positivo")
    })
})

test_that("reset_parallel_plan", {
    f <- reset_parallel_plan
    expect_true(is.function(f))

    test_that("reset_parallel_plan restaura plano anterior", {
        withr::defer(future::plan("sequential"))
        future::plan("sequential")
        old <- setup_parallel_plan(workers = 2L)
        expect_equal(get_parallel_config()$workers, 2L)

        f(old)
        cfg <- get_parallel_config()
        expect_equal(cfg$strategy, "sequential")
    })

    test_that("reset_parallel_plan retorna invisible NULL", {
        withr::defer(future::plan("sequential"))
        old <- setup_parallel_plan(strategy = "sequential")
        result <- f(old)
        expect_null(result)
    })
})

test_that("get_parallel_config", {
    f <- get_parallel_config
    expect_true(is.function(f))

    test_that("get_parallel_config retorna estrutura correta", {
        withr::defer(future::plan("sequential"))
        setup_parallel_plan(workers = 2L, strategy = "multisession")
        cfg <- f()

        expect_true(is.list(cfg))
        expect_named(cfg, c("workers", "strategy"))
        expect_true(is.numeric(cfg$workers))
        expect_true(is.character(cfg$strategy))
    })

    test_that("get_parallel_config reflete plano sequential", {
        withr::defer(future::plan("sequential"))
        setup_parallel_plan(strategy = "sequential")
        cfg <- f()

        expect_equal(cfg$strategy, "sequential")
        expect_equal(cfg$workers, 1L)
    })

    test_that("get_parallel_config reflete plano multisession", {
        withr::defer(future::plan("sequential"))
        setup_parallel_plan(workers = 2L, strategy = "multisession")
        cfg <- f()

        expect_equal(cfg$strategy, "multisession")
        expect_equal(cfg$workers, 2L)
    })
})

test_that("validate_workers", {
    f <- mhpfv:::validate_workers
    expect_true(is.function(f))

    test_that("validate_workers aceita NULL", {
        expect_silent(f(NULL))
    })

    test_that("validate_workers aceita inteiro positivo", {
        expect_silent(f(1L))
        expect_silent(f(4L))
    })

    test_that("validate_workers rejeita valores invalidos", {
        expect_error(f(-1L), "inteiro positivo")
        expect_error(f(0L), "inteiro positivo")
        expect_error(f(2.5), "inteiro positivo")
        expect_error(f(NA_integer_), "inteiro positivo")
        expect_error(f("2"), "inteiro positivo")
    })
})
