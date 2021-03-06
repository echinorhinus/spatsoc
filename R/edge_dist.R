#' Distance based edge lists
#'
#'
#' \code{edge_dist} returns edge lists defined by a spatial distance within the
#' user defined threshold. The function accepts a \code{data.table} with
#' relocation data, individual identifiers and a threshold argument. The
#' threshold argument is used to specify the criteria for distance between
#' points which defines a group. Relocation data should be in two columns
#' representing the X and Y coordinates.
#'
#'
#' The \code{DT} must be a \code{data.table}. If your data is a
#' \code{data.frame}, you can convert it by reference using
#' \code{\link[data.table:setDT]{data.table::setDT}}.
#'
#' The \code{id}, \code{coords} (and optional \code{timegroup} and
#' \code{splitBy}) arguments expect the names of a column in \code{DT} which
#' correspond to the individual identifier, X and Y coordinates, timegroup
#' (generated by \code{group_times}) and additional grouping columns.
#'
#' The \code{threshold} must be provided in the units of the coordinates. The
#' \code{threshold} must be larger than 0. The coordinates must be planar
#' coordinates (e.g.: UTM). In the case of UTM, a \code{threshold} = 50 would
#' indicate a 50m distance threshold.
#'
#' The \code{timegroup} argument is optional, but recommended to pair with
#' \code{\link{group_times}}. The intended framework is to group rows temporally
#' with \code{\link{group_times}} then spatially with \code{edge_dist} (or
#' grouping functions).
#'
#' The \code{splitBy} argument offers further control over grouping. If within
#' your \code{DT}, you have multiple populations, subgroups or other distinct
#' parts, you can provide the name of the column which identifies them to
#' \code{splitBy}. \code{edge_dist} will only consider rows within each
#' \code{splitBy} subgroup.
#'
#' @inheritParams group_pts
#' @param returnDist boolean indicating if the distance between individuals
#'   should be returned. If FALSE (default), only ID1, ID2 columns (and
#'   timegroup, splitBy columns if provided) are returned. If TRUE, another
#'   column "distance" is returned indicating the distance between ID1 and ID2.
#' @param fillNA boolean indicating if NAs should be returned for individuals
#'   that were not within the threshold distance of any other. If TRUE, NAs are
#'   returned. If FALSE, only edges between individuals within the threshold
#'   distance are returned.
#'
#' @return \code{edge_dist} returns a \code{data.table} with columns ID1, ID2,
#'   timegroup (if supplied) and any columns provided in splitBy. If
#'   'returnDist' is TRUE, column 'distance' is returned indicating the distance
#'   between ID1 and ID2.
#'
#'   The ID1 and ID2 columns represent the edges defined by the spatial (and
#'   temporal with \code{group_times}) thresholds.
#'
#' @export
#'
#' @family Edge-list generation
#'
#' @examples
#' # Load data.table
#' library(data.table)
#'
#' # Read example data
#' DT <- fread(system.file("extdata", "DT.csv", package = "spatsoc"))
#'
#' # Cast the character column to POSIXct
#' DT[, datetime := as.POSIXct(datetime, tz = 'UTC')]
#'
#' # Temporal grouping
#' group_times(DT, datetime = 'datetime', threshold = '20 minutes')
#'
#' # Edge list generation
#' edges <- edge_dist(
#'     DT,
#'     threshold = 100,
#'     id = 'ID',
#'     coords = c('X', 'Y'),
#'     timegroup = 'timegroup',
#'     returnDist = TRUE,
#'     fillNA = TRUE
#'   )
edge_dist <- function(DT = NULL,
                      threshold = NULL,
                      id = NULL,
                      coords = NULL,
                      timegroup,
                      splitBy = NULL,
                      returnDist = FALSE,
                      fillNA = TRUE) {
  # due to NSE notes in R CMD check
  N <- Var1 <- Var2 <- value <- . <- NULL

  if (is.null(DT)) {
    stop('input DT required')
  }

  if (is.null(threshold)) {
    stop('threshold required')
  }

  if (!is.numeric(threshold)) {
    stop('threshold must be numeric')
  }

  if (threshold <= 0) {
    stop('threshold must be greater than 0')
  }

  if (is.null(id)) {
    stop('ID field required')
  }

  if (length(coords) != 2) {
    stop('coords requires a vector of column names for coordinates X and Y')
  }

  if (missing(timegroup)) {
    stop('timegroup required')
  }

  if (any(!(
    c(timegroup, id, coords, splitBy) %in% colnames(DT)
  ))) {
    stop(paste0(
      as.character(paste(setdiff(
        c(timegroup, id, coords, splitBy),
        colnames(DT)
      ), collapse = ', ')),
      ' field(s) provided are not present in input DT'
    ))
  }

  if (any(!(DT[, vapply(.SD, is.numeric, TRUE), .SDcols = coords]))) {
    stop('coords must be numeric')
  }

  if (!is.null(timegroup)) {
    if (any(unlist(lapply(DT[, .SD, .SDcols = timegroup], class)) %in%
            c('POSIXct', 'POSIXlt', 'Date', 'IDate', 'ITime', 'character'))) {
      warning(
        strwrap(
          prefix = " ",
          initial = "",
          x = 'timegroup provided is a date/time
          or character type, did you use group_times?'
        )
        )
    }
  }

  if (is.null(timegroup) && is.null(splitBy)) {
    splitBy <- NULL
  } else {
    splitBy <- c(splitBy, timegroup)
    if (DT[, .N, by = c(id, splitBy, timegroup)][N > 1, sum(N)] != 0) {
      warning(
        strwrap(
          prefix = " ",
          initial = "",
          x = 'found duplicate id in a
          timegroup and/or splitBy -
          does your group_times threshold match the fix rate?'
        )
      )
    }
  }

  edges <- DT[, {

    distMatrix <-
      as.matrix(stats::dist(.SD[, 2:3], method = 'euclidean'))
    diag(distMatrix) <- NA

    w <- which(distMatrix < threshold, arr.ind = TRUE)

    if (returnDist) {
      l <- list(ID1 = .SD[[1]][w[, 1]],
                ID2 = .SD[[1]][w[, 2]],
                distance = distMatrix[w])
    } else {
      l <- list(ID1 = .SD[[1]][w[, 1]],
                ID2 = .SD[[1]][w[, 2]])
    }
    l
  },
  by = splitBy, .SDcols = c(id, coords)]

  if (fillNA) {
    merge(edges,
          unique(DT[, .SD, .SDcols = c(splitBy, id)]),
          by.x = c(splitBy, 'ID1'),
          by.y = c(splitBy, id),
          all = TRUE)
  } else {
    return(edges)
  }
}

