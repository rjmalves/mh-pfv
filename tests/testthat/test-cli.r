test_that("cli_main errors on invalid datadir", {
    expect_error(cli_main(datadir = "/nonexistent/path"))
})

test_that("cli_main connects and parses config", {
    skip_if_not(dir.exists(test_path("data")))
    conn <- conectamock_pfv(test_path("data"))
    config <- get_config(conn)
    parsed <- parse_config(config, conn)
    expect_true(parsed$mode %in% c("train", "predict"))
})

test_that("cli_main errors on invalid mode with Modo invalido", {
    skip_if_not(dir.exists(test_path("data")))

    tmp_data <- withr::local_tempdir()
    src_files <- list.files(test_path("data"), full.names = TRUE)
    file.copy(src_files, tmp_data)

    config_path <- file.path(tmp_data, "config.jsonc")
    config_text <- readLines(config_path, warn = FALSE)
    config_text <- gsub('"train"', '"invalid_mode"', config_text)
    writeLines(config_text, config_path)

    expect_error(cli_main(datadir = tmp_data), "Modo invalido")
})
