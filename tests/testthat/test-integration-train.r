test_that("train_main completes without error", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    expect_no_error(train_main(config))
})

test_that("train_main produces valid model artifacts", {
    skip_if_not(dir.exists(test_path("data")))
    temp_artifact <- withr::local_tempdir()

    conn <- conectamock_pfv(test_path("data"))
    config <- gen_config(
        mode = "train",
        janela = list("2025-07-01", "2025-09-30")
    )
    config$input <- test_path("data")
    config$artifact <- temp_artifact
    config <- parse_config(config, conn)

    train_main(config)

    expected_ids <- config$ids_usinas
    artifact_files <- file.path(
        temp_artifact, paste0(expected_ids, ".rds")
    )

    expect_true(all(file.exists(artifact_files)))
    expect_equal(length(artifact_files), length(expected_ids))

    hhmm_pattern <- "^(0[5-9]|1[0-8]):[0-3]0$"

    for (i in seq_along(artifact_files)) {
        artifact <- readRDS(artifact_files[i])

        expect_true(is.list(artifact))
        expect_true(all(c("id_usina", "parametros") %in% names(artifact)))

        expect_true(is.character(artifact$id_usina))
        expect_equal(artifact$id_usina, expected_ids[i])

        params <- artifact$parametros
        expect_true(is.data.frame(params))
        expect_true(all(c("a", "b") %in% names(params)))

        rnames <- rownames(params)
        expect_true(all(grepl(hhmm_pattern, rnames)))

        rnames_as_hours <- as.numeric(
            sub("^(\\d+):(\\d+)$", "\\1", rnames)
        ) + as.numeric(
            sub("^(\\d+):(\\d+)$", "\\2", rnames)
        ) / 60
        expect_true(all(rnames_as_hours >= 5.0))
        expect_true(all(rnames_as_hours <= 18.5))

        non_na_b <- params$b[!is.na(params$b)]
        expect_true(all(non_na_b == 0))

        non_na_a <- params$a[!is.na(params$a)]
        expect_true(all(is.finite(non_na_a)))
        expect_true(all(is.numeric(non_na_a)))
    }
})
