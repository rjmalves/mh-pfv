gen_provenance_completed <- function(ids = c("USI1", "USI2"), mode = "train") {
    cfg <- gen_config(
        ids_usinas = ids,
        janela = list("2025-07-01", "2025-09-30")
    )
    prov <- create_provenance(cfg, mode, FALSE)
    for (iu in ids) {
        prov <- update_plant_status(prov, iu, "completed")
    }
    finalize_provenance(prov, "completed")
}

gen_provenance_failed <- function(ids = c("USI1", "USI2"), mode = "train") {
    cfg <- gen_config(
        ids_usinas = ids,
        janela = list("2025-07-01", "2025-09-30")
    )
    prov <- create_provenance(cfg, mode, FALSE)
    prov <- update_plant_status(prov, ids[1], "failed")
    if (length(ids) > 1L) {
        for (iu in ids[-1L]) {
            prov <- update_plant_status(prov, iu, "completed")
        }
    }
    finalize_provenance(prov, "failed")
}

gen_metrics_healthy <- function(ids = c("USI1", "USI2"), mode = "train") {
    run_id <- paste0(mode, "-20260101-120000-abcd")
    m <- create_metrics(run_id, mode)
    for (iu in ids) {
        m <- record_plant_timing(m, iu, 5.0)
        m <- record_plant_data_volume(m, iu, 1440, 100, 1440)
        if (mode == "train") {
            m <- record_model_quality(m, iu, list(
                n_slots = 28L, n_valid_slots = 26L, mean_coefficient = 0.031
            ))
        }
    }
    finalize_metrics(m)
}

gen_metrics_high_na <- function(ids = c("USI1", "USI2"), mode = "train",
    bad_id = NULL) {

    if (is.null(bad_id)) bad_id <- ids[1L]
    run_id <- paste0(mode, "-20260101-120000-abcd")
    m <- create_metrics(run_id, mode)
    for (iu in ids) {
        m <- record_plant_timing(m, iu, 5.0)
        n_na <- if (iu == bad_id) 900 else 100
        m <- record_plant_data_volume(m, iu, 1440, n_na, 1440)
    }
    finalize_metrics(m)
}

gen_metrics_low_slots <- function(ids = c("USI1", "USI2"), bad_id = NULL) {
    if (is.null(bad_id)) bad_id <- ids[1L]
    run_id <- "train-20260101-120000-abcd"
    m <- create_metrics(run_id, "train")
    for (iu in ids) {
        m <- record_plant_timing(m, iu, 5.0)
        m <- record_plant_data_volume(m, iu, 1440, 100, 1440)
        n_valid <- if (iu == bad_id) 5L else 26L
        m <- record_model_quality(m, iu, list(
            n_slots = 28L, n_valid_slots = n_valid, mean_coefficient = 0.02
        ))
    }
    finalize_metrics(m)
}

test_that("classify_plant_health", {
    f <- mhpfv:::classify_plant_health
    expect_true(is.function(f))

    test_that("classify_plant_health returns failed for failed provenance status", {
        result <- f("failed", NULL)
        expect_equal(result, "failed")
    })

    test_that("classify_plant_health returns failed for pending provenance status", {
        result <- f("pending", NULL)
        expect_equal(result, "failed")
    })

    test_that("classify_plant_health returns failed for skipped provenance status", {
        result <- f("skipped", NULL)
        expect_equal(result, "failed")
    })

    test_that("classify_plant_health returns healthy for completed plant with no metrics", {
        result <- f("completed", NULL)
        expect_equal(result, "healthy")
    })

    test_that("classify_plant_health returns healthy for completed plant with good metrics", {
        plant_metrics <- list(
            duration_seconds = 5.0,
            data_volume = list(n_rows = 1440L, n_na = 100L, na_rate = 0.069),
            model_quality = list(n_slots = 28L, n_valid_slots = 26L, mean_coefficient = 0.031)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "healthy")
    })

    test_that("classify_plant_health returns warning for na_rate > 0.5", {
        plant_metrics <- list(
            data_volume = list(n_rows = 1440L, n_na = 900L, na_rate = 0.625)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "warning")
    })

    test_that("classify_plant_health returns healthy for na_rate exactly 0.5", {
        plant_metrics <- list(
            data_volume = list(n_rows = 100L, n_na = 50L, na_rate = 0.5)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "healthy")
    })

    test_that("classify_plant_health returns warning for n_valid_slots < n_slots * 0.5", {
        plant_metrics <- list(
            model_quality = list(n_slots = 28L, n_valid_slots = 5L, mean_coefficient = 0.02)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "warning")
    })

    test_that("classify_plant_health returns healthy for n_valid_slots >= n_slots * 0.5", {
        plant_metrics <- list(
            model_quality = list(n_slots = 28L, n_valid_slots = 14L, mean_coefficient = 0.02)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "healthy")
    })

    test_that("classify_plant_health returns warning when only data_volume triggers it", {
        plant_metrics <- list(
            data_volume = list(n_rows = 1440L, n_na = 900L, na_rate = 0.625),
            model_quality = list(n_slots = 28L, n_valid_slots = 26L, mean_coefficient = 0.031)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "warning")
    })

    test_that("classify_plant_health handles NA na_rate gracefully", {
        plant_metrics <- list(
            data_volume = list(n_rows = 0L, n_na = 0L, na_rate = NA_real_)
        )
        result <- f("completed", plant_metrics)
        expect_equal(result, "healthy")
    })
})

test_that("classify_overall_health", {
    f <- mhpfv:::classify_overall_health
    expect_true(is.function(f))

    test_that("classify_overall_health returns healthy when all plants healthy", {
        prov <- list(status = "completed")
        healths <- c(USI1 = "healthy", USI2 = "healthy")
        expect_equal(f(prov, healths), "healthy")
    })

    test_that("classify_overall_health returns degraded when some plants have warning", {
        prov <- list(status = "completed")
        healths <- c(USI1 = "warning", USI2 = "healthy")
        expect_equal(f(prov, healths), "degraded")
    })

    test_that("classify_overall_health returns failed for failed provenance", {
        prov <- list(status = "failed")
        healths <- c(USI1 = "healthy", USI2 = "healthy")
        expect_equal(f(prov, healths), "failed")
    })

    test_that("classify_overall_health returns failed when any plant failed", {
        prov <- list(status = "completed")
        healths <- c(USI1 = "failed", USI2 = "healthy")
        expect_equal(f(prov, healths), "failed")
    })

    test_that("classify_overall_health prioritizes failed over degraded", {
        prov <- list(status = "completed")
        healths <- c(USI1 = "failed", USI2 = "warning")
        expect_equal(f(prov, healths), "failed")
    })

    test_that("classify_overall_health returns healthy for running provenance with healthy plants", {
        prov <- list(status = "running")
        healths <- c(USI1 = "healthy")
        result <- f(prov, healths)
        expect_equal(result, "healthy")
    })

    test_that("classify_overall_health handles empty plant_healths vector", {
        prov <- list(status = "completed")
        healths <- character(0L)
        expect_equal(f(prov, healths), "healthy")
    })
})

test_that("collect_warnings", {
    f <- mhpfv:::collect_warnings
    expect_true(is.function(f))

    test_that("collect_warnings returns empty vector for all healthy plants", {
        reports <- list(
            USI1 = list(health = "healthy", data_quality = list(na_rate = 0.05, n_rows = 1440L),
                model_quality = list(n_slots = 28L, n_valid_slots = 26L)),
            USI2 = list(health = "healthy", data_quality = NULL, model_quality = NULL)
        )
        result <- f(reports)
        expect_equal(result, character(0L))
        expect_equal(length(result), 0L)
    })

    test_that("collect_warnings returns Portuguese message for high NA rate", {
        reports <- list(
            USI1 = list(
                health = "warning",
                data_quality = list(na_rate = 0.833, n_rows = 1440L),
                model_quality = NULL
            )
        )
        result <- f(reports)
        expect_equal(length(result), 1L)
        expect_true(grepl("USI1", result[1L]))
        expect_true(grepl("NA", result[1L]))
        expect_true(grepl("83.3", result[1L]))
    })

    test_that("collect_warnings returns Portuguese message for low valid slots", {
        reports <- list(
            USI1 = list(
                health = "warning",
                data_quality = NULL,
                model_quality = list(n_slots = 28L, n_valid_slots = 5L)
            )
        )
        result <- f(reports)
        expect_equal(length(result), 1L)
        expect_true(grepl("USI1", result[1L]))
        expect_true(grepl("5", result[1L]))
        expect_true(grepl("28", result[1L]))
    })

    test_that("collect_warnings emits both messages when plant has two quality issues", {
        reports <- list(
            USI1 = list(
                health = "warning",
                data_quality = list(na_rate = 0.9, n_rows = 1440L),
                model_quality = list(n_slots = 28L, n_valid_slots = 3L)
            )
        )
        result <- f(reports)
        expect_equal(length(result), 2L)
    })

    test_that("collect_warnings skips failed plants", {
        reports <- list(
            USI1 = list(health = "failed", data_quality = NULL, model_quality = NULL)
        )
        result <- f(reports)
        expect_equal(result, character(0L))
    })

    test_that("collect_warnings collects messages across multiple warning plants", {
        reports <- list(
            USI1 = list(
                health = "warning",
                data_quality = list(na_rate = 0.8, n_rows = 1440L),
                model_quality = NULL
            ),
            USI2 = list(
                health = "warning",
                data_quality = list(na_rate = 0.7, n_rows = 1440L),
                model_quality = NULL
            )
        )
        result <- f(reports)
        expect_equal(length(result), 2L)
        expect_true(any(grepl("USI1", result)))
        expect_true(any(grepl("USI2", result)))
    })
})

test_that("collect_errors", {
    f <- mhpfv:::collect_errors
    expect_true(is.function(f))

    test_that("collect_errors returns empty vector for no failed plants", {
        reports <- list(
            USI1 = list(health = "healthy"),
            USI2 = list(health = "warning")
        )
        result <- f(reports)
        expect_equal(result, character(0L))
    })

    test_that("collect_errors returns Portuguese message for failed plant", {
        reports <- list(
            USI1 = list(health = "failed")
        )
        result <- f(reports)
        expect_equal(length(result), 1L)
        expect_true(grepl("USI1", result[1L]))
        expect_true(grepl("falhou", result[1L]))
    })

    test_that("collect_errors collects messages for multiple failed plants", {
        reports <- list(
            USI1 = list(health = "failed"),
            USI2 = list(health = "healthy"),
            USI3 = list(health = "failed")
        )
        result <- f(reports)
        expect_equal(length(result), 2L)
        expect_true(any(grepl("USI1", result)))
        expect_true(any(grepl("USI3", result)))
    })
})

test_that("build_plant_reports", {
    f <- mhpfv:::build_plant_reports
    expect_true(is.function(f))

    test_that("build_plant_reports returns named list keyed by plant ID", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_healthy(c("USI1", "USI2"))
        result <- f(prov, metrics)

        expect_true(is.list(result))
        expect_true("USI1" %in% names(result))
        expect_true("USI2" %in% names(result))
    })

    test_that("build_plant_reports populates expected fields per plant", {
        prov <- gen_provenance_completed(c("USI1"))
        metrics <- gen_metrics_healthy(c("USI1"))
        result <- f(prov, metrics)

        plant <- result$USI1
        expect_true("health" %in% names(plant))
        expect_true("provenance_status" %in% names(plant))
        expect_true("duration_seconds" %in% names(plant))
        expect_true("data_quality" %in% names(plant))
        expect_true("model_quality" %in% names(plant))
    })

    test_that("build_plant_reports sets data_quality and model_quality to NULL when metrics is NULL", {
        prov <- gen_provenance_completed(c("USI1"))
        result <- f(prov, NULL)

        expect_null(result$USI1$data_quality)
        expect_null(result$USI1$model_quality)
        expect_null(result$USI1$duration_seconds)
    })

    test_that("build_plant_reports marks plant as failed when provenance status is failed", {
        prov <- gen_provenance_failed(c("USI1", "USI2"))
        metrics <- gen_metrics_healthy(c("USI1", "USI2"))
        result <- f(prov, metrics)

        expect_equal(result$USI1$health, "failed")
    })

    test_that("build_plant_reports populates data_quality from metrics data_volume", {
        prov <- gen_provenance_completed(c("USI1"))
        metrics <- gen_metrics_healthy(c("USI1"), mode = "predict")
        result <- f(prov, metrics)

        dq <- result$USI1$data_quality
        expect_false(is.null(dq))
        expect_true("na_rate" %in% names(dq))
        expect_true("n_rows" %in% names(dq))
    })
})

test_that("build_health_report", {
    f <- build_health_report
    expect_true(is.function(f))

    test_that("build_health_report returns complete structure with all expected fields", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_healthy(c("USI1", "USI2"))
        result <- f(prov, metrics)

        expected_fields <- c(
            "run_id", "mode", "created_at", "overall_health",
            "summary", "plants", "warnings", "errors"
        )
        expect_true(all(expected_fields %in% names(result)))
    })

    test_that("build_health_report summary has all required fields", {
        prov <- gen_provenance_completed(c("USI1"))
        result <- f(prov)

        summary_fields <- c(
            "status", "duration_seconds", "n_plants",
            "n_plants_completed", "n_plants_failed", "n_plants_warning",
            "package_version", "config_hash"
        )
        expect_true(all(summary_fields %in% names(result$summary)))
    })

    test_that("build_health_report overall_health is healthy for all-completed run", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_healthy(c("USI1", "USI2"))
        result <- f(prov, metrics)

        expect_equal(result$overall_health, "healthy")
    })

    test_that("build_health_report overall_health is degraded when plant has high NA", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_high_na(c("USI1", "USI2"), bad_id = "USI1")
        result <- f(prov, metrics)

        expect_equal(result$overall_health, "degraded")
        expect_equal(result$plants$USI1$health, "warning")
    })

    test_that("build_health_report overall_health is failed when provenance failed", {
        prov <- gen_provenance_failed(c("USI1", "USI2"))
        metrics <- gen_metrics_healthy(c("USI1", "USI2"))
        result <- f(prov, metrics)

        expect_equal(result$overall_health, "failed")
    })

    test_that("build_health_report summary counts are correct for mixed plant statuses", {
        prov <- gen_provenance_completed(c("USI1", "USI2", "USI3"))
        metrics <- gen_metrics_high_na(c("USI1", "USI2", "USI3"), bad_id = "USI1")
        result <- f(prov, metrics)

        expect_equal(result$summary$n_plants, 3L)
        expect_equal(result$summary$n_plants_warning, 1L)
        expect_equal(result$summary$n_plants_failed, 0L)
        expect_equal(result$summary$n_plants_completed, 3L)
    })

    test_that("build_health_report handles metrics = NULL gracefully", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        result <- f(prov, NULL)

        expect_true(is.list(result))
        expect_equal(result$overall_health, "healthy")
        expect_null(result$plants$USI1$data_quality)
        expect_null(result$plants$USI1$model_quality)
    })

    test_that("build_health_report populates warnings array for high NA plants", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_high_na(c("USI1", "USI2"), bad_id = "USI1")
        result <- f(prov, metrics)

        expect_true(length(result$warnings) > 0L)
        expect_true(any(grepl("USI1", result$warnings)))
    })

    test_that("build_health_report populates errors array for failed plants", {
        prov <- gen_provenance_failed(c("USI1", "USI2"))
        result <- f(prov, NULL)

        expect_true(length(result$errors) > 0L)
        expect_true(any(grepl("USI1", result$errors)))
    })

    test_that("build_health_report warnings is character(0L) when no warnings", {
        prov <- gen_provenance_completed(c("USI1"))
        result <- f(prov, NULL)

        expect_equal(result$warnings, character(0L))
    })

    test_that("build_health_report errors is character(0L) when no errors", {
        prov <- gen_provenance_completed(c("USI1"))
        result <- f(prov, NULL)

        expect_equal(result$errors, character(0L))
    })

    test_that("build_health_report created_at is ISO 8601 UTC string", {
        prov <- gen_provenance_completed(c("USI1"))
        result <- f(prov)

        iso_pattern <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$"
        expect_match(result$created_at, iso_pattern)
    })

    test_that("build_health_report run_id and mode match provenance", {
        prov <- gen_provenance_completed(c("USI1"), mode = "predict")
        result <- f(prov)

        expect_equal(result$run_id, prov$run_id)
        expect_equal(result$mode, "predict")
    })

    test_that("build_health_report validates provenance is list", {
        expect_error(f("not a list"))
        expect_error(f(NULL))
    })

    test_that("build_health_report overall_health degraded for low valid slots", {
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_low_slots(c("USI1", "USI2"), bad_id = "USI1")
        result <- f(prov, metrics)

        expect_equal(result$overall_health, "degraded")
        expect_equal(result$plants$USI1$health, "warning")
        expect_equal(result$plants$USI2$health, "healthy")
    })
})

test_that("write_health_report", {
    f <- write_health_report
    expect_true(is.function(f))

    test_that("write_health_report writes valid JSON file to temp directory", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov)

        filepath <- f(report, tmp)

        expected_name <- paste0("health-", prov$run_id, ".json")
        expect_true(file.exists(file.path(tmp, expected_name)))
    })

    test_that("write_health_report file name matches health-{run_id}.json pattern", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov)

        filepath <- f(report, tmp)

        expect_match(basename(filepath), "^health-train-.*\\.json$")
    })

    test_that("write_health_report produces parseable JSON with correct structure", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_healthy(c("USI1", "USI2"))
        report <- build_health_report(prov, metrics)

        filepath <- f(report, tmp)
        parsed <- jsonlite::fromJSON(filepath)

        expect_equal(parsed$run_id, prov$run_id)
        expect_equal(parsed$mode, "train")
        expect_true("overall_health" %in% names(parsed))
        expect_true("summary" %in% names(parsed))
        expect_true("plants" %in% names(parsed))
    })

    test_that("write_health_report creates directory if missing", {
        tmp <- withr::local_tempdir()
        nested <- file.path(tmp, "deep", "nested", "dir")
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov)

        filepath <- f(report, nested)

        expect_true(dir.exists(nested))
        expect_true(file.exists(filepath))
    })

    test_that("write_health_report does not throw on invalid directory", {
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov)

        suppressWarnings(
            expect_no_error(f(report, "/proc/nonexistent/path/that/cannot/be/created"))
        )
    })

    test_that("write_health_report returns filepath invisibly", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov)

        result <- f(report, tmp)

        expected <- file.path(tmp, paste0("health-", prov$run_id, ".json"))
        expect_equal(result, expected)
    })

    test_that("write_health_report roundtrip: warnings array serializes as JSON array", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1", "USI2"))
        metrics <- gen_metrics_high_na(c("USI1", "USI2"), bad_id = "USI1")
        report <- build_health_report(prov, metrics)

        filepath <- f(report, tmp)
        parsed <- jsonlite::fromJSON(filepath)

        expect_true(is.character(parsed$warnings))
        expect_true(length(parsed$warnings) > 0L)
    })

    test_that("write_health_report serializes empty warnings as JSON array", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov)

        filepath <- f(report, tmp)
        raw_text <- paste(readLines(filepath), collapse = "\n")

        expect_true(grepl('"warnings":\\s*\\[\\s*\\]', raw_text))
    })

    test_that("write_health_report serializes NULL data_quality as null in JSON", {
        tmp <- withr::local_tempdir()
        prov <- gen_provenance_completed(c("USI1"))
        report <- build_health_report(prov, NULL)

        filepath <- f(report, tmp)
        raw_text <- paste(readLines(filepath), collapse = "\n")

        expect_true(grepl("null", raw_text))
    })
})
