# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Builder — installs build tools and restores all R packages via renv
# =============================================================================
FROM rocker/r-ver:4.5.3 AS builder

ARG MHPFV_VERSION=0.1.1
ARG GITHUB_PAT

# ---- System build dependencies -----------------------------------------------
# build-essential / cmake: compile packages with C/C++ code (arrow, data.table)
# libcurl4-openssl-dev / libssl-dev: arrow HTTP/TLS support at build time
# libxml2-dev: xml2 (transitive dep of some packages)
# zlib1g-dev / libzstd-dev: ZSTD codec for arrow Parquet support
# python3 / python3-dev: argparse R package delegates to Python at build time
# git: renv needs git to install GitHub-sourced packages (pfvIO, dbinterface)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    curl \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libzstd-dev \
    python3 \
    python3-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# ARROW_WITH_ZSTD: ensures ZSTD codec is included when arrow compiles from source.
# RENV_CONFIG_REPOS_OVERRIDE: routes CRAN packages through PPM for pre-built Linux binaries.
ENV ARROW_WITH_ZSTD=ON \
    RENV_CONFIG_PPM_ENABLED=TRUE

WORKDIR /app

# ---- renv bootstrap and package install --------------------------------------
RUN mkdir -p renv
COPY renv.lock       renv.lock
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json
COPY .Rprofile       .Rprofile
COPY DESCRIPTION DESCRIPTION
COPY NAMESPACE   NAMESPACE
COPY R/          R/
COPY main.r      main.r

RUN R -e "renv::restore(confirm = FALSE); renv::install('.', rebuild = TRUE)" && \
    for lib in $(R -s -e "cat(.libPaths(), sep='\n')"); do \
        cp -rLn "$lib"/* /usr/local/lib/R/site-library/ 2>/dev/null || true; \
    done

# =============================================================================
# Stage 2: Runtime — minimal image with only runtime libraries and entrypoint
# =============================================================================
FROM rocker/r-ver:4.5.3

ARG MHPFV_VERSION=0.1.1

LABEL org.opencontainers.image.title="mhpfv" \
    org.opencontainers.image.description="Consolidação de histórico de geração solar fotovoltaica" \
    org.opencontainers.image.vendor="ONS - Operador Nacional do Sistema Elétrico" \
    org.opencontainers.image.source="https://github.com/rjmalves/mh-pfv" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="${MHPFV_VERSION}"

# ---- Runtime system dependencies ---------------------------------------------
# libcurl4-openssl-dev / libssl-dev: arrow C++ library needs these at runtime
#   (missing causes segfault, not a clean R error)
# libzstd-dev: ZSTD codec used by arrow for Parquet compression/decompression
# python3: argparse R package shells out to Python's argparse module at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libzstd-dev \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# ---- Copy installed R library from builder -----------------------------------
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
COPY --from=builder /usr/local/lib/R/library       /usr/local/lib/R/library

# ---- Non-root user -----------------------------------------------------------
RUN useradd -r -s /bin/false appuser

# ---- Application code --------------------------------------------------------
WORKDIR /app
COPY --chown=appuser:appuser main.r main.r

# ---- Runtime environment -----------------------------------------------------
ENV LOG_LEVEL=info
ENV MHPFV_PARALLEL=false
ENV MHPFV_RESUME=false
ENV MHPFV_WORKERS=

# ---- Health check ------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD Rscript -e "library(mhpfv); cat('OK')" || exit 1

USER appuser

ENTRYPOINT ["Rscript", "main.r"]
CMD ["--datadir", "/app/data"]
