FROM rocker/tidyverse:4.4.2

WORKDIR /app

COPY DESCRIPTION DESCRIPTION
COPY NAMESPACE NAMESPACE
COPY R/ R/
COPY main.r main.r

RUN mkdir -p renv/
COPY renv.lock renv.lock
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json
COPY .Rprofile .Rprofile

RUN R -e "renv::restore()"

RUN R -e "install.packages('remotes')"
RUN R -e "remotes::install_local('.', dependencies = FALSE, upgrade = 'never')"

ENTRYPOINT [ "Rscript", "main.r"]