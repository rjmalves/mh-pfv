suppressPackageStartupMessages(library(pfvIO))
suppressPackageStartupMessages(library(mhpfv))

lg <- get_pkg_logger()

parser <- get_parser()
args <- parser$parse_args()

conn <- conectamock_pfv(args$datadir)
config <- get_config(conn)
config <- parse_config(config, conn)

tryCatch(
    {
        if (config$mode == "train") {
            train_main(config)
        } else if (config$mode == "predict") {
            predict_main(config)
        } else {
            stop("Modo invalido. Apenas os modos 'train' e 'predict' estao disponiveis para esse modelo.")
        }
        q(status = 0)
    },
    error = function(e) {
        lg$error(e)
        q(status = 1)
    }
)
