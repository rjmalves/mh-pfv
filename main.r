suppressPackageStartupMessages(library(mhpfv))

parser <- get_parser()
args <- parser$parse_args()

tryCatch(
    {
        cli_main(args$datadir)
        q(status = 0)
    },
    error = function(e) {
        lg <- get_pkg_logger()
        lg$error(e)
        q(status = 1)
    }
)
