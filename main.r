library(melhorhistoricosolar)

lg <- get_pkg_logger()

tryCatch(
    {
        parser <- get_parser()
        args <- parser$parse_args()
        if (args$mode == "predict") {
            predict_main(args)
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
