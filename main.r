suppressPackageStartupMessages(library(pfvIO))
suppressPackageStartupMessages(library(melhorhistoricosolar))

lg <- get_pkg_logger()

parser <- get_parser()
args <- parser$parse_args()

conn <- conectamock_pfv(args$datadir)
config <- get_config(conn)
config <- parse_config(config, conn)

tryCatch(
    {
        if (config$mode == "predict") {
            predict_main(config)
        } else {
            stop("Modo invalido. Apenas o modo 'predict' esta disponivel para esse modelo.")
        }
        q(status = 0)
    },
    error = function(e) {
        lg$error(e)
        q(status = 1)
    }
)
