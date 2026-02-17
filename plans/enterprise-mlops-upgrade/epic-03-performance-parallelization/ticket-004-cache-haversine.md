# E03-T004 Cache Haversine Distance Computations

## Context

### Background

The `associa_nwp_usina()` function in `R/utils.r` computes the Haversine distance between every plant and every NWP grid point to find the nearest forecast coordinate for each plant. The plant coordinates (latitude/longitude from `dt_usinas`) and NWP grid coordinates (unique lat/lon from `dt_irrad_prev`) do not change between calls within the same R session. After E03-T002 and E03-T003 hoist `associa_nwp_usina` out of per-plant loops, the function is called once per `train_main` and once per `predict_main` invocation. However, in batch workflows where both train and predict run in the same session, or when the function is called multiple times with the same inputs, the distance matrix is recomputed redundantly.

This ticket adds memoization to `associa_nwp_usina()` so that the Haversine distance computation is cached based on the plant and NWP coordinate sets. This is ONLY about caching the distance computation -- the hoisting of `associa_nwp_usina` out of loops is done in E03-T002/T003, not here.

### Relation to Epic

This ticket is independent of the parallelization chain (E03-T001 -> T002 -> T003). It addresses a pure computational efficiency concern. The cache benefits any workflow that calls `associa_nwp_usina()` more than once with the same coordinate sets.

### Current State

`R/utils.r`, function `associa_nwp_usina()` (lines 226-271):

```r
associa_nwp_usina <- function(dt_usinas, dt_irrad_prev) {
    coord_prev <- unique(dt_irrad_prev[, .(latitude, longitude)])
    lista_filtrados <- lapply(seq_len(nrow(dt_usinas)), function(i) {
        usina <- dt_usinas[i]
        raio_km <- 6371
        coord_prev[, distancia := 2 * raio_km * asin(sqrt(
            sin(((latitude - usina$latitude) * pi / 180) / 2)^2 +
                cos(usina$latitude * pi / 180) * cos(latitude * pi / 180) *
                    sin(((longitude - usina$longitude) * pi / 180) / 2)^2
        ))]
        coord_mais_proxima <- coord_prev[which.min(distancia)]
        dt_filt <- dt_irrad_prev[
            latitude == coord_mais_proxima$latitude &
                longitude == coord_mais_proxima$longitude
        ]
        dt_filt[, id_usina := usina$id_usina]
        return(dt_filt)
    })
    dt_irrad_prev_filt <- rbindlist(lista_filtrados)
    setcolorder(dt_irrad_prev_filt, c(
        "id_modelo_nwp", "id_usina",
        setdiff(names(dt_irrad_prev_filt), c("id_modelo_nwp", "id_usina"))
    ))
    return(dt_irrad_prev_filt)
}
```

Key observations:

- `coord_prev` is computed from `unique(dt_irrad_prev[, .(latitude, longitude)])`.
- The Haversine computation is inside the `lapply` and modifies `coord_prev` by reference (`:=`).
- For N plants and M grid points, the function computes N\*M Haversine distances.
- The NWP grid coordinates are fixed for a given model/region. Plant coordinates change rarely.

There is no caching infrastructure in the package currently.

## Specification

### Requirements

1. **Create a private cache environment** in `R/utils.r` (or a new `R/cache.r` if preferred) using `new.env(parent = emptyenv())`. This environment stores cached nearest-coordinate mappings keyed by a digest of the input coordinates.

2. **Extract the Haversine nearest-coordinate computation** into an internal helper function `find_nearest_nwp_coords(dt_usinas, coord_prev)` that returns a data.table mapping `id_usina -> nearest_latitude, nearest_longitude`.

3. **Add memoization to `find_nearest_nwp_coords`**: Before computing, generate a cache key from the sorted plant coordinates and sorted NWP coordinates (e.g., using `paste0(collapse)` or `digest::digest` if available, or a simple hash from the coordinate values). Check the cache environment; if hit, return the cached mapping. If miss, compute, store, and return.

4. **Refactor `associa_nwp_usina`** to call `find_nearest_nwp_coords` for the mapping, then use the mapping to filter `dt_irrad_prev` (the join/filter logic). This separates the expensive computation (Haversine) from the data filtering (cheap).

5. **Add `clear_haversine_cache()`** exported function to allow callers to invalidate the cache when coordinates change. Document it with roxygen2.

6. **Do NOT add external dependencies** for caching. Use a plain R environment. Avoid `memoise` or `digest` as new dependencies -- use base R for the cache key (e.g., `paste(sort(coords), collapse = "|")`).

7. **Do NOT hoist `associa_nwp_usina` out of loops** -- that is done in E03-T002/T003. This ticket focuses solely on memoizing the distance computation.

### Inputs/Props

- `find_nearest_nwp_coords(dt_usinas, coord_prev)`:
  - `dt_usinas`: data.table with columns `id_usina`, `latitude`, `longitude`.
  - `coord_prev`: data.table with columns `latitude`, `longitude` (unique NWP coordinates).
  - Returns: data.table with columns `id_usina`, `nearest_latitude`, `nearest_longitude`.

- `clear_haversine_cache()`: No arguments. Clears all cached mappings.

### Outputs/Behavior

- `associa_nwp_usina()` returns the exact same output as before -- a data.table of filtered irradiance predictions with `id_usina` column added. The caching is transparent to callers.
- On the first call with a given set of coordinates, the Haversine distances are computed normally.
- On subsequent calls with the same coordinates, the cached mapping is used, skipping the Haversine computation entirely.
- `clear_haversine_cache()` resets the cache. The next call recomputes from scratch.

### Error Handling

- If the cache key generation fails for any reason, fall back to computing without caching (log a warning via `lgr`).
- The cache should never cause a functional error -- it is a pure performance optimization. If anything goes wrong with the cache, the function should still produce correct results.

## Acceptance Criteria

- [ ] Given `associa_nwp_usina(dt_usinas, dt_irrad_prev)` is called twice with the same inputs, when the second call executes, then the Haversine computation is skipped (verify via timing: second call is faster, or via internal counter/mock).
- [ ] Given `associa_nwp_usina()` is called with cached and non-cached inputs, when results are compared, then they are identical.
- [ ] Given `clear_haversine_cache()` is called between two identical `associa_nwp_usina()` calls, when the second call executes, then the Haversine computation runs again.
- [ ] Given `associa_nwp_usina()` is called with different `dt_usinas` (different plants), when the cache is inspected, then both mappings are cached independently.
- [ ] Given the existing test suite is run, when results are checked, then all `associa_nwp_usina` tests still pass without modification.
- [ ] Given `devtools::check()` is run, when it completes, then there are no new ERRORs or WARNINGs.

## Implementation Guide

### Suggested Approach

**Step 1: Create the cache environment**

At the top of `R/utils.r` (module level, outside any function):

```r
# Private cache for Haversine nearest-coordinate mappings
.haversine_cache <- new.env(parent = emptyenv())
```

**Step 2: Create `make_coord_key()` helper**

```r
make_coord_key <- function(dt_usinas, coord_prev) {
    plant_part <- paste(
        dt_usinas$id_usina,
        dt_usinas$latitude,
        dt_usinas$longitude,
        collapse = "|"
    )
    nwp_part <- paste(
        sort(paste(coord_prev$latitude, coord_prev$longitude)),
        collapse = "|"
    )
    paste(plant_part, nwp_part, sep = "##")
}
```

**Step 3: Extract `find_nearest_nwp_coords()`**

Move the Haversine computation logic into this function. It takes `dt_usinas` and `coord_prev`, returns the mapping data.table:

```r
find_nearest_nwp_coords <- function(dt_usinas, coord_prev) {
    key <- make_coord_key(dt_usinas, coord_prev)
    if (exists(key, envir = .haversine_cache)) {
        return(get(key, envir = .haversine_cache))
    }

    raio_km <- 6371
    mapping <- rbindlist(lapply(seq_len(nrow(dt_usinas)), function(i) {
        usina <- dt_usinas[i]
        # Use a copy to avoid modifying coord_prev by reference
        cp <- copy(coord_prev)
        cp[, distancia := 2 * raio_km * asin(sqrt(
            sin(((latitude - usina$latitude) * pi / 180) / 2)^2 +
                cos(usina$latitude * pi / 180) * cos(latitude * pi / 180) *
                    sin(((longitude - usina$longitude) * pi / 180) / 2)^2
        ))]
        nearest <- cp[which.min(distancia)]
        data.table(
            id_usina = usina$id_usina,
            nearest_latitude = nearest$latitude,
            nearest_longitude = nearest$longitude
        )
    }))

    assign(key, mapping, envir = .haversine_cache)
    mapping
}
```

**Step 4: Refactor `associa_nwp_usina()`**

```r
associa_nwp_usina <- function(dt_usinas, dt_irrad_prev) {
    coord_prev <- unique(dt_irrad_prev[, .(latitude, longitude)])
    mapping <- find_nearest_nwp_coords(dt_usinas, coord_prev)

    lista_filtrados <- lapply(seq_len(nrow(mapping)), function(i) {
        row <- mapping[i]
        dt_filt <- dt_irrad_prev[
            latitude == row$nearest_latitude &
                longitude == row$nearest_longitude
        ]
        dt_filt[, id_usina := row$id_usina]
        dt_filt
    })

    dt_irrad_prev_filt <- rbindlist(lista_filtrados)
    setcolorder(dt_irrad_prev_filt, c(
        "id_modelo_nwp", "id_usina",
        setdiff(names(dt_irrad_prev_filt), c("id_modelo_nwp", "id_usina"))
    ))
    return(dt_irrad_prev_filt)
}
```

**Step 5: Add `clear_haversine_cache()`**

```r
#' Limpa Cache de Distancias Haversine
#'
#' Remove todos os mapeamentos de coordenadas NWP-usina armazenados em cache.
#' Use quando as coordenadas das usinas ou do grid NWP mudarem.
#'
#' @return `invisible(NULL)`
#'
#' @export
clear_haversine_cache <- function() {
    rm(list = ls(.haversine_cache), envir = .haversine_cache)
    invisible(NULL)
}
```

**Step 6: Write tests**

### Key Files to Modify

- `/home/rogerio/git/mh-pfv/R/utils.r` -- add cache environment, extract `find_nearest_nwp_coords`, refactor `associa_nwp_usina`, add `clear_haversine_cache`
- `/home/rogerio/git/mh-pfv/tests/testthat/test-utils.r` -- add cache tests

### Patterns to Follow

- The private environment pattern (`new.env(parent = emptyenv())`) is a standard R idiom for package-level caching. It avoids global state pollution.
- Use `copy(coord_prev)` inside the distance computation to avoid modifying the shared `coord_prev` by reference -- the current code modifies it via `:=`, which would corrupt it across iterations.
- Export only `clear_haversine_cache()`. Keep `find_nearest_nwp_coords()` and `make_coord_key()` as internal (non-exported) helpers.
- Roxygen2 documentation in Portuguese, matching existing style.

### Pitfalls to Avoid

- The current code modifies `coord_prev` by reference with `coord_prev[, distancia := ...]`. Inside `find_nearest_nwp_coords`, use `copy(coord_prev)` per iteration to prevent this side effect. This is a correctness bug fix that the current code gets away with because the loop re-sets `distancia` each iteration, but it would be dangerous with caching.
- Do NOT use `digest::digest()` for the cache key -- that would add a new dependency. Plain `paste()` with sorted coordinates is sufficient for this use case. The coordinate sets are small (typically < 100 plants, < 1000 grid points).
- The cache environment persists for the R session. In long-running processes, call `clear_haversine_cache()` explicitly if coordinates change. Document this clearly.
- Do NOT cache the full filtered irradiance data.table -- only cache the coordinate mapping. The data filtering (which is cheap) must always run to handle different `dt_irrad_prev` data with the same coordinates.

## Testing Requirements

### Unit Tests

File: `tests/testthat/test-utils.r` (add to existing `associa_nwp_usina` test block)

1. `associa_nwp_usina()` with cache produces same results as without cache (compare output data.tables).
2. Second call with same inputs uses cache (measure timing or inspect cache environment directly).
3. `clear_haversine_cache()` forces recomputation on next call.
4. Different plant coordinates produce different cache entries (both stored independently).
5. `find_nearest_nwp_coords()` returns correct mapping structure (`id_usina`, `nearest_latitude`, `nearest_longitude`).
6. Existing `associa_nwp_usina` tests pass without modification (backward compatibility).

### Integration Tests

Not applicable for this ticket -- the cache is transparent to callers and does not affect pipeline integration behavior.

## Dependencies

- **Blocked By**: E02-T004 (extensibility refactor complete)
- **Blocks**: None

## Effort Estimate

**Points**: 2
**Confidence**: High
