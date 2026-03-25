test_that("create_metrics", {
    f <- create_metrics
    expect_true(is.function(f))

    test_that("create_metrics returns correct structure", {
        result <- f("train-20260101-120000-abcd", "train")

        expect_true(is.list(result))
        expect_equal(result$run_id, "train-20260101-120000-abcd")
        expect_equal(result$mode, "train")
        expect_null(result$created_at)
        expect_true(is.list(result$pipeline))
        expect_equal(length(result$pipeline), 0L)
        expect_true(is.list(result$plants))
        expect_equal(length(result$plants), 0L)
    })

    test_that("create_metrics works for predict mode", {
        result <- f("predict-20260101-120000-abcd", "predict")

        expect_equal(result$mode, "predict")
        expect_equal(result$run_id, "predict-20260101-120000-abcd")
    })

    test_that("create_metrics rejects non-character run_id", {
        expect_error(f(123L, "train"))
        expect_error(f(NULL, "train"))
    })

    test_that("create_metrics rejects non-character mode", {
        expect_error(f("run-id", 1L))
        expect_error(f("run-id", NULL))
    })

    test_that("create_metrics rejects vector run_id", {
        expect_error(f(c("a", "b"), "train"))
    })

    test_that("create_metrics rejects vector mode", {
        expect_error(f("run-id", c("train", "predict")))
    })
})

test_that("record_plant_timing", {
    f <- record_plant_timing

    expect_true(is.function(f))

    test_that("record_plant_timing adds duration_seconds for single plant", {
        m <- create_metrics("test-run", "train")
        result <- f(m, "USI1", 5.3)

        expect_equal(result$plants$USI1$duration_seconds, 5.3)
    })

    test_that("record_plant_timing preserves existing plant fields", {
        m <- create_metrics("test-run", "train")
        m$plants$USI1 <- list(model_quality = list(n_slots = 28L))
        result <- f(m, "USI1", 5.3)

        expect_equal(result$plants$USI1$duration_seconds, 5.3)
        expect_equal(result$plants$USI1$model_quality$n_slots, 28L)
    })

    test_that("record_plant_timing records timing for multiple plants independently", {
        m <- create_metrics("test-run", "train")
        m <- f(m, "USI1", 3.1)
        m <- f(m, "USI2", 7.8)
        m <- f(m, "USI3", 1.5)

        expect_equal(m$plants$USI1$duration_seconds, 3.1)
        expect_equal(m$plants$USI2$duration_seconds, 7.8)
        expect_equal(m$plants$USI3$duration_seconds, 1.5)
    })

    test_that("record_plant_timing rejects non-numeric duration", {
        m <- create_metrics("test-run", "train")

        expect_error(f(m, "USI1", "five"))
        expect_error(f(m, "USI1", NULL))
        expect_error(f(m, "USI1", TRUE))
    })

    test_that("record_plant_timing rejects vector duration", {
        m <- create_metrics("test-run", "train")

        expect_error(f(m, "USI1", c(1.0, 2.0)))
    })

    test_that("record_plant_timing rejects non-character id_usina", {
        m <- create_metrics("test-run", "train")

        expect_error(f(m, 1L, 5.0))
    })

    test_that("record_plant_timing rejects non-list metrics", {
        expect_error(f("not-a-list", "USI1", 5.0))
    })

    test_that("record_plant_timing returns updated copy without modifying original", {
        m <- create_metrics("test-run", "train")
        result <- f(m, "USI1", 5.0)

        expect_null(m$plants$USI1)
        expect_equal(result$plants$USI1$duration_seconds, 5.0)
    })
})

test_that("record_plant_data_volume", {
    f <- record_plant_data_volume

    expect_true(is.function(f))

    test_that("record_plant_data_volume records correct structure", {
        m <- create_metrics("test-run", "predict")
        result <- f(m, "USI1", 1440, 120, 1440)

        expect_true(is.list(result$plants$USI1$data_volume))
        expect_equal(result$plants$USI1$data_volume$n_rows, 1440L)
        expect_equal(result$plants$USI1$data_volume$n_na, 120L)
        expect_equal(result$plants$USI1$data_volume$na_rate, round(120 / 1440, 4L))
    })

    test_that("record_plant_data_volume computes na_rate correctly", {
        m <- create_metrics("test-run", "predict")
        result <- f(m, "USI1", 100, 25, 100)

        expect_equal(result$plants$USI1$data_volume$na_rate, 0.25)
    })

    test_that("record_plant_data_volume handles n_total = 0 as NA na_rate", {
        m <- create_metrics("test-run", "predict")
        result <- f(m, "USI1", 0, 0, 0)

        expect_true(is.na(result$plants$USI1$data_volume$na_rate))
    })

    test_that("record_plant_data_volume stores n_rows and n_na as integers", {
        m <- create_metrics("test-run", "predict")
        result <- f(m, "USI1", 1440.0, 120.0, 1440.0)

        expect_type(result$plants$USI1$data_volume$n_rows, "integer")
        expect_type(result$plants$USI1$data_volume$n_na, "integer")
    })

    test_that("record_plant_data_volume preserves existing plant fields", {
        m <- create_metrics("test-run", "predict")
        m$plants$USI1 <- list(duration_seconds = 3.5)
        result <- f(m, "USI1", 100, 5, 100)

        expect_equal(result$plants$USI1$duration_seconds, 3.5)
        expect_equal(result$plants$USI1$data_volume$n_rows, 100L)
    })

    test_that("record_plant_data_volume rejects non-numeric n_rows", {
        m <- create_metrics("test-run", "predict")

        expect_error(f(m, "USI1", "one hundred", 0, 100))
    })

    test_that("record_plant_data_volume rejects vector inputs", {
        m <- create_metrics("test-run", "predict")

        expect_error(f(m, "USI1", c(100, 200), 0, 100))
    })
})

test_that("record_model_quality", {
    f <- record_model_quality

    expect_true(is.function(f))

    test_that("record_model_quality extracts n_slots and n_valid_slots", {
        m <- create_metrics("test-run", "train")
        meta <- list(
            type = "linear_regression",
            n_slots = 28L,
            n_valid_slots = 26L,
            timestamp = Sys.time(),
            package_version = "0.1.0",
            config_hash = "abc123"
        )
        result <- f(m, "USI1", meta)

        expect_equal(result$plants$USI1$model_quality$n_slots, 28L)
        expect_equal(result$plants$USI1$model_quality$n_valid_slots, 26L)
    })

    test_that("record_model_quality preserves existing plant fields", {
        m <- create_metrics("test-run", "train")
        m$plants$USI1 <- list(duration_seconds = 4.2)
        meta <- list(n_slots = 28L, n_valid_slots = 28L)
        result <- f(m, "USI1", meta)

        expect_equal(result$plants$USI1$duration_seconds, 4.2)
        expect_equal(result$plants$USI1$model_quality$n_slots, 28L)
    })

    test_that("record_model_quality handles NULL metadata fields gracefully", {
        m <- create_metrics("test-run", "train")
        meta <- list(n_slots = 28L, n_valid_slots = NULL)
        result <- f(m, "USI1", meta)

        expect_equal(result$plants$USI1$model_quality$n_slots, 28L)
        expect_null(result$plants$USI1$model_quality$n_valid_slots)
    })

    test_that("record_model_quality rejects non-list metadata", {
        m <- create_metrics("test-run", "train")

        expect_error(f(m, "USI1", "not-a-list"))
        expect_error(f(m, "USI1", NULL))
    })

    test_that("record_model_quality rejects non-list metrics", {
        expect_error(f("not-a-list", "USI1", list()))
    })
})

test_that("finalize_metrics", {
    f <- finalize_metrics

    expect_true(is.function(f))

    test_that("finalize_metrics computes correct aggregates from per-plant timing", {
        m <- create_metrics("test-run", "train")
        m <- record_plant_timing(m, "USI1", 3.0)
        m <- record_plant_timing(m, "USI2", 7.0)
        m <- record_plant_timing(m, "USI3", 5.0)
        result <- f(m)

        expect_equal(result$pipeline$n_plants, 3L)
        expect_equal(result$pipeline$n_plants_completed, 3L)
        expect_equal(result$pipeline$mean_plant_duration_seconds, 5.0)
        expect_equal(result$pipeline$max_plant_duration_seconds, 7.0)
        expect_equal(result$pipeline$min_plant_duration_seconds, 3.0)
    })

    test_that("finalize_metrics handles single plant correctly", {
        m <- create_metrics("test-run", "train")
        m <- record_plant_timing(m, "USI1", 4.5)
        result <- f(m)

        expect_equal(result$pipeline$n_plants_completed, 1L)
        expect_equal(result$pipeline$mean_plant_duration_seconds, 4.5)
        expect_equal(result$pipeline$max_plant_duration_seconds, 4.5)
        expect_equal(result$pipeline$min_plant_duration_seconds, 4.5)
    })

    test_that("finalize_metrics returns NA aggregates for empty plants list", {
        m <- create_metrics("test-run", "train")
        result <- f(m)

        expect_equal(result$pipeline$n_plants, 0L)
        expect_equal(result$pipeline$n_plants_completed, 0L)
        expect_true(is.na(result$pipeline$mean_plant_duration_seconds))
        expect_true(is.na(result$pipeline$max_plant_duration_seconds))
        expect_true(is.na(result$pipeline$min_plant_duration_seconds))
    })

    test_that("finalize_metrics returns NA aggregates when no plant has timing", {
        m <- create_metrics("test-run", "train")
        m <- record_model_quality(m, "USI1", list(n_slots = 28L, n_valid_slots = 28L))
        result <- f(m)

        expect_equal(result$pipeline$n_plants, 1L)
        expect_equal(result$pipeline$n_plants_completed, 0L)
        expect_true(is.na(result$pipeline$mean_plant_duration_seconds))
    })

    test_that("finalize_metrics sets created_at as ISO 8601 UTC string", {
        m <- create_metrics("test-run", "train")
        result <- f(m)

        expect_false(is.null(result$created_at))
        expect_true(grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", result$created_at))
    })

    test_that("finalize_metrics counts only plants with duration_seconds", {
        m <- create_metrics("test-run", "train")
        m <- record_plant_timing(m, "USI1", 3.0)
        m$plants$USI2 <- list(model_quality = list(n_slots = 28L))
        result <- f(m)

        expect_equal(result$pipeline$n_plants, 2L)
        expect_equal(result$pipeline$n_plants_completed, 1L)
    })

    test_that("finalize_metrics rejects non-list input", {
        expect_error(f("not-a-list"))
        expect_error(f(NULL))
    })
})

test_that("write_metrics", {
    f <- write_metrics

    expect_true(is.function(f))

    test_that("write_metrics writes valid JSON to a temp directory", {
        m <- create_metrics("test-run-001", "train")
        m <- record_plant_timing(m, "USI1", 5.0)
        m <- finalize_metrics(m)
        out_dir <- withr::local_tempdir()

        f(m, out_dir)

        expected_path <- file.path(out_dir, "metrics-test-run-001.json")
        expect_true(file.exists(expected_path))
    })

    test_that("write_metrics produces parseable JSON", {
        m <- create_metrics("test-roundtrip", "predict")
        m <- record_plant_timing(m, "USI1", 2.5)
        m <- record_plant_data_volume(m, "USI1", 100, 10, 100)
        m <- finalize_metrics(m)
        out_dir <- withr::local_tempdir()

        f(m, out_dir)

        parsed <- jsonlite::fromJSON(
            file.path(out_dir, "metrics-test-roundtrip.json")
        )
        expect_equal(parsed$run_id, "test-roundtrip")
        expect_equal(parsed$mode, "predict")
        expect_equal(parsed$pipeline$n_plants, 1L)
        expect_equal(parsed$pipeline$n_plants_completed, 1L)
    })

    test_that("write_metrics creates output directory if missing", {
        m <- create_metrics("test-mkdir", "train")
        m <- finalize_metrics(m)
        out_dir <- file.path(withr::local_tempdir(), "nested", "subdir")

        expect_false(dir.exists(out_dir))
        f(m, out_dir)

        expect_true(dir.exists(out_dir))
        expect_true(file.exists(file.path(out_dir, "metrics-test-mkdir.json")))
    })

    test_that("write_metrics does not throw on invalid output directory", {
        m <- create_metrics("test-error", "train")
        m <- finalize_metrics(m)

        suppressWarnings(
            expect_no_error(f(m, "/proc/nonexistent/path/that/cannot/be/created"))
        )
    })

    test_that("write_metrics returns filepath invisibly", {
        m <- create_metrics("test-invisible", "train")
        m <- finalize_metrics(m)
        out_dir <- withr::local_tempdir()

        result <- f(m, out_dir)

        expect_equal(result, file.path(out_dir, "metrics-test-invisible.json"))
    })

    test_that("write_metrics serializes NA aggregates as null in JSON", {
        m <- create_metrics("test-na-null", "train")
        m <- finalize_metrics(m)
        out_dir <- withr::local_tempdir()

        f(m, out_dir)

        raw_json <- readLines(file.path(out_dir, "metrics-test-na-null.json"))
        raw_text <- paste(raw_json, collapse = "\n")
        expect_true(grepl("null", raw_text))
    })
})
