test_that("generate_run_id", {
    f <- generate_run_id
    expect_true(is.function(f))

    test_that("generate_run_id produces correct format for train", {
        rid <- f("train")
        pattern <- "^train-\\d{8}-\\d{6}-[0-9a-f]{4}$"
        expect_match(rid, pattern)
    })

    test_that("generate_run_id produces correct format for predict", {
        rid <- f("predict")
        pattern <- "^predict-\\d{8}-\\d{6}-[0-9a-f]{4}$"
        expect_match(rid, pattern)
    })

    test_that("generate_run_id produces unique IDs", {
        ids <- vapply(seq_len(100), function(i) f("train"), character(1))
        expect_equal(length(unique(ids)), 100L)
    })

    test_that("generate_run_id validates mode is character", {
        expect_error(f(123))
        expect_error(f(NULL))
        expect_error(f(c("train", "predict")))
    })
})

test_that("create_provenance", {
    f <- create_provenance
    expect_true(is.function(f))

    test_that("create_provenance returns complete structure", {
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- f(cfg, "train", FALSE)

        expected_fields <- c(
            "run_id", "mode", "package_version", "r_version",
            "start_time", "end_time", "duration_seconds", "config_hash",
            "n_plants", "plant_ids", "plant_status", "parallel", "status"
        )
        expect_true(all(expected_fields %in% names(prov)))
    })

    test_that("create_provenance sets correct initial values", {
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- f(cfg, "train", FALSE)

        expect_equal(prov$mode, "train")
        expect_equal(prov$status, "running")
        expect_null(prov$end_time)
        expect_null(prov$duration_seconds)
        expect_false(prov$parallel)
        expect_equal(prov$n_plants, 2L)
        expect_equal(prov$plant_ids, c("USI1", "USI2"))
        expect_s3_class(prov$start_time, "POSIXct")
    })

    test_that("create_provenance initializes all plants as pending", {
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2", "USI3"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- f(cfg, "predict", TRUE)

        expect_true(is.list(prov$plant_status))
        expect_equal(names(prov$plant_status), c("USI1", "USI2", "USI3"))
        expect_true(all(vapply(prov$plant_status, identity, character(1)) == "pending"))
        expect_true(prov$parallel)
    })

    test_that("create_provenance computes config_hash", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- f(cfg, "train", FALSE)

        expect_true(is.character(prov$config_hash))
        expect_true(nchar(prov$config_hash) > 0L)
    })
})

test_that("update_plant_status", {
    f <- update_plant_status
    expect_true(is.function(f))

    test_that("update_plant_status updates single plant", {
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- f(prov, "USI1", "completed")

        expect_equal(prov$plant_status$USI1, "completed")
        expect_equal(prov$plant_status$USI2, "pending")
    })

    test_that("update_plant_status accepts all valid statuses", {
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2", "USI3"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        prov <- f(prov, "USI1", "completed")
        prov <- f(prov, "USI2", "failed")
        prov <- f(prov, "USI3", "skipped")

        expect_equal(prov$plant_status$USI1, "completed")
        expect_equal(prov$plant_status$USI2, "failed")
        expect_equal(prov$plant_status$USI3, "skipped")
    })

    test_that("update_plant_status rejects invalid status", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        expect_error(f(prov, "USI1", "invalid"))
        expect_error(f(prov, "USI1", ""))
    })

    test_that("update_plant_status validates inputs", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        expect_error(f("not_a_list", "USI1", "completed"))
        expect_error(f(prov, 123, "completed"))
        expect_error(f(prov, c("USI1", "USI2"), "completed"))
    })
})

test_that("finalize_provenance", {
    f <- finalize_provenance
    expect_true(is.function(f))

    test_that("finalize_provenance sets timing fields", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- f(prov, "completed")

        expect_s3_class(prov$end_time, "POSIXct")
        expect_true(is.numeric(prov$duration_seconds))
        expect_true(prov$duration_seconds >= 0)
    })

    test_that("finalize_provenance sets completed status", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- f(prov, "completed")

        expect_equal(prov$status, "completed")
    })

    test_that("finalize_provenance sets failed status", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- f(prov, "failed")

        expect_equal(prov$status, "failed")
    })

    test_that("finalize_provenance rejects invalid status", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        expect_error(f(prov, "invalid"))
        expect_error(f(prov, "running"))
    })

    test_that("finalize_provenance validates provenance is list", {
        expect_error(f("not_a_list", "completed"))
    })
})

test_that("write_provenance", {
    f <- write_provenance
    expect_true(is.function(f))

    test_that("write_provenance creates valid JSON", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- update_plant_status(prov, "USI1", "completed")
        prov <- update_plant_status(prov, "USI2", "completed")
        prov <- finalize_provenance(prov, "completed")

        filepath <- f(prov, tmp)

        expect_true(file.exists(filepath))
        expect_match(basename(filepath), "^provenance-train-.*\\.json$")

        parsed <- jsonlite::fromJSON(filepath)
        expect_equal(parsed$run_id, prov$run_id)
        expect_equal(parsed$mode, "train")
        expect_equal(parsed$status, "completed")
        expect_equal(parsed$n_plants, 2L)
        expect_true(is.character(parsed$start_time))
        expect_true(is.character(parsed$end_time))
    })

    test_that("write_provenance handles missing directory", {
        tmp <- withr::local_tempdir()
        nested <- file.path(tmp, "deep", "nested", "dir")
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- finalize_provenance(prov, "completed")

        filepath <- f(prov, nested)

        expect_true(dir.exists(nested))
        expect_true(file.exists(filepath))
    })

    test_that("write_provenance does not throw on write failure", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- finalize_provenance(prov, "completed")

        expect_no_error(f(prov, "/proc/nonexistent/path"))
    })

    test_that("write_provenance serializes timestamps as ISO 8601", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- finalize_provenance(prov, "completed")

        filepath <- f(prov, tmp)
        parsed <- jsonlite::fromJSON(filepath)

        iso_pattern <- "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$"
        expect_match(parsed$start_time, iso_pattern)
        expect_match(parsed$end_time, iso_pattern)
    })

    test_that("write_provenance handles NULL end_time for running record", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        filepath <- f(prov, tmp)

        expect_true(file.exists(filepath))
        parsed <- jsonlite::fromJSON(filepath)
        expect_equal(parsed$status, "running")
        expect_null(parsed$end_time)
    })
})

test_that("format_provenance_timestamps", {
    f <- mhpfv:::format_provenance_timestamps
    expect_true(is.function(f))

    test_that("format_provenance_timestamps converts POSIXct to string", {
        prov <- list(
            start_time = as.POSIXct("2026-02-17 14:30:52", tz = "UTC"),
            end_time = as.POSIXct("2026-02-17 14:31:15", tz = "UTC")
        )
        result <- f(prov)

        expect_equal(result$start_time, "2026-02-17T14:30:52Z")
        expect_equal(result$end_time, "2026-02-17T14:31:15Z")
    })

    test_that("format_provenance_timestamps preserves NULL end_time", {
        prov <- list(
            start_time = as.POSIXct("2026-02-17 14:30:52", tz = "UTC"),
            end_time = NULL
        )
        result <- f(prov)

        expect_true(is.character(result$start_time))
        expect_null(result$end_time)
    })
})

test_that("write_checkpoint", {
    f <- mhpfv:::write_checkpoint
    expect_true(is.function(f))

    test_that("write_checkpoint creates checkpoint file", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        filepath <- f(prov, tmp)

        expect_true(file.exists(filepath))
        expect_match(basename(filepath), "^checkpoint-train-.*\\.json$")
    })

    test_that("write_checkpoint writes valid JSON", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- update_plant_status(prov, "USI1", "completed")

        filepath <- f(prov, tmp)

        parsed <- jsonlite::fromJSON(filepath, simplifyVector = FALSE)
        expect_equal(parsed$run_id, prov$run_id)
        expect_equal(parsed$plant_status$USI1, "completed")
    })

    test_that("write_checkpoint does not throw on I/O failure", {
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        expect_no_error(f(prov, "/proc/nonexistent/path"))
    })

    test_that("write_checkpoint creates directory if missing", {
        tmp <- withr::local_tempdir()
        nested <- file.path(tmp, "deep", "nested")
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)

        filepath <- f(prov, nested)

        expect_true(dir.exists(nested))
        expect_true(file.exists(filepath))
    })
})

test_that("read_checkpoint", {
    f <- mhpfv:::read_checkpoint
    expect_true(is.function(f))

    test_that("read_checkpoint returns NULL for empty directory", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )

        result <- f(tmp, cfg)

        expect_null(result)
    })

    test_that("read_checkpoint reads a valid checkpoint", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- update_plant_status(prov, "USI1", "completed")
        mhpfv:::write_checkpoint(prov, tmp)

        result <- f(tmp, cfg)

        expect_false(is.null(result))
        expect_equal(result$run_id, prov$run_id)
        expect_equal(result$plant_status$USI1, "completed")
        expect_equal(result$plant_status$USI2, "pending")
    })

    test_that("read_checkpoint returns NULL for config hash mismatch", {
        tmp <- withr::local_tempdir()
        cfg_a <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )
        cfg_b <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2024-01-01", "2024-03-31")
        )
        prov <- create_provenance(cfg_a, "train", FALSE)
        mhpfv:::write_checkpoint(prov, tmp)

        result <- expect_no_warning(f(tmp, cfg_b))

        expect_null(result)
    })

    test_that("read_checkpoint returns NULL for corrupted file", {
        tmp <- withr::local_tempdir()
        bad_file <- file.path(tmp, "checkpoint-train-bad.json")
        writeLines("{ this is not valid json !!!}", bad_file)

        result <- f(tmp, gen_config())

        expect_null(result)
    })

    test_that("read_checkpoint picks most recent checkpoint", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )

        prov1 <- create_provenance(cfg, "train", FALSE)
        prov1 <- update_plant_status(prov1, "USI1", "completed")
        mhpfv:::write_checkpoint(prov1, tmp)

        Sys.sleep(1.1)

        prov2 <- create_provenance(cfg, "train", FALSE)
        prov2 <- update_plant_status(prov2, "USI1", "completed")
        prov2 <- update_plant_status(prov2, "USI2", "completed")
        mhpfv:::write_checkpoint(prov2, tmp)

        result <- f(tmp, cfg)

        expect_equal(result$run_id, prov2$run_id)
        expect_equal(result$plant_status$USI2, "completed")
    })
})

test_that("get_pending_plants", {
    f <- mhpfv:::get_pending_plants
    expect_true(is.function(f))

    test_that("get_pending_plants returns non-completed plant IDs", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2", "USI3"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- update_plant_status(prov, "USI1", "completed")
        prov <- update_plant_status(prov, "USI3", "failed")
        mhpfv:::write_checkpoint(prov, tmp)

        checkpoint <- jsonlite::fromJSON(
            list.files(tmp, full.names = TRUE)[1],
            simplifyVector = FALSE
        )

        result <- f(checkpoint)

        expect_true("USI2" %in% result)
        expect_true("USI3" %in% result)
        expect_false("USI1" %in% result)
    })

    test_that("get_pending_plants returns empty vector when all completed", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        prov <- update_plant_status(prov, "USI1", "completed")
        prov <- update_plant_status(prov, "USI2", "completed")
        mhpfv:::write_checkpoint(prov, tmp)

        checkpoint <- jsonlite::fromJSON(
            list.files(tmp, full.names = TRUE)[1],
            simplifyVector = FALSE
        )

        result <- f(checkpoint)

        expect_equal(length(result), 0L)
    })
})

test_that("write_plant_result", {
    f <- mhpfv:::write_plant_result
    expect_true(is.function(f))

    test_that("write_plant_result creates RDS file", {
        tmp <- withr::local_tempdir()
        result <- list(
            com_cortes = data.table::data.table(valor = 1:3),
            sem_cortes = data.table::data.table(valor = 4:6)
        )

        filepath <- f(result, "USI1", tmp)

        expect_true(file.exists(filepath))
        expect_match(basename(filepath), "^plant-result-USI1\\.rds$")
    })

    test_that("write_plant_result does not throw on I/O failure", {
        result <- list(
            com_cortes = data.table::data.table(valor = 1:3),
            sem_cortes = data.table::data.table(valor = 4:6)
        )

        expect_no_error(f(result, "USI1", "/proc/nonexistent/path"))
    })
})

test_that("read_plant_result", {
    f <- mhpfv:::read_plant_result
    expect_true(is.function(f))

    test_that("read_plant_result returns NULL for missing file", {
        tmp <- withr::local_tempdir()

        result <- f("USI_MISSING", tmp)

        expect_null(result)
    })

    test_that("read_plant_result roundtrip preserves data", {
        tmp <- withr::local_tempdir()
        original <- list(
            com_cortes = data.table::data.table(
                id_usina = "USI1", valor = c(1.0, 2.0, 3.0)
            ),
            sem_cortes = data.table::data.table(
                id_usina = "USI1", valor = c(4.0, 5.0, 6.0)
            )
        )
        mhpfv:::write_plant_result(original, "USI1", tmp)

        result <- f("USI1", tmp)

        expect_false(is.null(result))
        expect_equal(result$com_cortes$valor, original$com_cortes$valor)
        expect_equal(result$sem_cortes$valor, original$sem_cortes$valor)
    })

    test_that("read_plant_result returns NULL for corrupted file", {
        tmp <- withr::local_tempdir()
        bad_path <- file.path(tmp, "plant-result-USIBAD.rds")
        writeLines("not an rds file", bad_path)

        result <- f("USIBAD", tmp)

        expect_null(result)
    })
})

test_that("cleanup_checkpoint", {
    f <- mhpfv:::cleanup_checkpoint
    expect_true(is.function(f))

    test_that("cleanup_checkpoint removes checkpoint and plant-result files", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1", "USI2"),
            janela = list("2025-07-01", "2025-09-30")
        )
        prov <- create_provenance(cfg, "train", FALSE)
        mhpfv:::write_checkpoint(prov, tmp)
        mhpfv:::write_plant_result(
            list(com_cortes = data.table::data.table(), sem_cortes = data.table::data.table()),
            "USI1", tmp
        )
        mhpfv:::write_plant_result(
            list(com_cortes = data.table::data.table(), sem_cortes = data.table::data.table()),
            "USI2", tmp
        )

        cp_before <- list.files(tmp, "^checkpoint-.*\\.json$")
        pr_before <- list.files(tmp, "^plant-result-.*\\.rds$")
        expect_equal(length(cp_before), 1L)
        expect_equal(length(pr_before), 2L)

        f(tmp)

        cp_after <- list.files(tmp, "^checkpoint-.*\\.json$")
        pr_after <- list.files(tmp, "^plant-result-.*\\.rds$")
        expect_equal(length(cp_after), 0L)
        expect_equal(length(pr_after), 0L)
    })

    test_that("cleanup_checkpoint is silent on empty directory", {
        tmp <- withr::local_tempdir()

        expect_no_error(f(tmp))
    })

    test_that("cleanup_checkpoint with run_id removes only matching checkpoint", {
        tmp <- withr::local_tempdir()
        cfg <- gen_config(
            ids_usinas = c("USI1"),
            janela = list("2025-07-01", "2025-09-30")
        )

        prov1 <- create_provenance(cfg, "train", FALSE)
        mhpfv:::write_checkpoint(prov1, tmp)

        prov2 <- create_provenance(cfg, "train", FALSE)
        mhpfv:::write_checkpoint(prov2, tmp)

        f(tmp, run_id = prov1$run_id)

        remaining <- list.files(tmp, "^checkpoint-.*\\.json$")
        expect_equal(length(remaining), 1L)
        expect_match(remaining[1], prov2$run_id)
    })
})
