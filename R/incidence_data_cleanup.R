##' Duplicate records in the case count are merged according to the
##' following rules.
##' Details
##' @title Merge dulplicate records in the incidence count.
##' @param case_count
##' @param cols_to_keep
##' @param merge_rule
##' @return duplicates free data frame
##' @author Sangeeta Bhatia
##' @export
merge_duplicates <- function(case_count,
                             cols_to_keep,
                             merge_rule = c("median")) {
  ####################################
  ### identify unique entries based on date and country columns
  ####################################

  case_count$DateCountry <- paste0(
    as.character(case_count$date),
    case_count$country
  )
  uniq_dat <- unique(case_count$DateCountry)

  ####################################
  ### merge duplicated entries where necessary
  ####################################

  cols_to_keep <- cols_to_keep[cols_to_keep %in% names(case_count)]
  chr_cols <- cols_to_keep[!cols_to_keep %in% c("date", "cases")]
  ### create a processed dataset ###
  duplicates_free <- purrr::map_dfr(uniq_dat, function(x) {
    out <- merge_dup_lines_DS1(case_count[which(case_count$DateCountry
      %in% x), ],
    cols_to_keep,
    rule = merge_rule
    )
    out <- mutate_at(out, chr_cols, as.character)
    out
  })
  duplicates_free
}


##' Filters the input data on species, disease and location
##'
##' @title Filter the case count for parameters of interest.
##' @param case_count
##' @param species
##' @param disease
##' @param location
##' @return
##' @author Sangeeta Bhatia
filter_case_count <- function(case_count, species, disease, location) {
  dplyr::filter(case_count, disease %in% disease &
    species %in% species &
    location %in% location)

  case_count
}



##' adds a column "cases" with appropriate case definition and
##' a column "date" with date extracted from timestamp
##' @title Update the case count with a column for dates and a column
##' for the appropriate case definition.
##' @param case_count
##' @param case_type
##' @return
##' @author Sangeeta Bhatia
##' @export
update_cases_column <- function(case_count, case_type = c(
                                  "scc", "sc",
                                  "cc", "scd",
                                  "sd", "cd",
                                  "ALL"
                                )) {

  ####################################
  ### add checks on input arguments ###
  ####################################

  case_type <- match.arg(case_type)

  ### create dates without time from issue_date

  case_count$date <- lubridate::mdy(case_count$issue_date)

  ##################################################################
  ### Create column called cases which comprises all relevant cases
  ### to be counted in incidence
  ##################################################################

  case_count$cases <- get_cases(case_count, case_type)
  case_count
}

# function to create a merged entry, separated by a slash
#
paste_single_col <- function(col_dup) {
  out <- paste(col_dup, collapse = " / ")
  return(out)
}

# Sum with na.rm = TRUE but if all nas, return NA instead of 0
#

sum_only_na_stays_na <- function(x) {
  if (all(is.na(x))) {
    out <- NA
  } else {
    out <- sum(x, na.rm = TRUE)
  }
  return(out)
}


# Gets appropriate case counts off dataframe
#

get_cases <- function(dat,
                      case_type = c(
                        "scc", "sc", "cc", "scd",
                        "sd", "cd", "ALL"
                      )) {
  case_type <- match.arg(case_type)

  if (case_type %in% "scc") {
    col <- apply(dat[, c("sc", "cc")], 1, sum_only_na_stays_na)
  } else if (case_type %in% "sc") {
    col <- dat$sc
  } else if (case_type %in% "cc") {
    col <- dat$cc
  } else if (case_type %in% "scd") {
    col <- apply(dat[, c("sd", "cd")], 1, sum_only_na_stays_na)
  } else if (case_type %in% "sd") {
    col <- dat$sd
  } else if (case_type %in% "cd") {
    col <- dat$cd
  } else if (case_type %in% "ALL") {
    col <- apply(
      dat[, c("sc", "cc", "sd", "cd")], 1,
      sum_only_na_stays_na
    )
  }

  col
}

# Check column names
check.columns <- function(case_count, good_colnames) {
  actual_colnames <- colnames(case_count)
  check_colnames <- lapply(good_colnames,
    FUN = function(x) x %in% actual_colnames
  ) %>%
    unlist()
  return(all(check_colnames))
}


##' Computes the prection interval for the (n + 1)th observation given
##' n observations. This interval is
##' [mu.hat - lambda.sample.var, mu.hat + lambda.sample.var] where
##' lambda = k * sqrt((n + 1)/n)
##' Unfortunate notation due to Saw et al ..
##' @references \url{https://www.jstor.org/stable/pdf/2683249.pdf}
##' @seealso \url{https://arxiv.org/pdf/1509.08398.pdf}
##' @title
##' @return
##' @author Sangeeta Bhatia
prediction_interval <- function(x, k) {
  n <- length(x)
  mu.hat <- mean(x, na.rm = TRUE) ## questionable?
  sd.hat <- sd(x, na.rm = TRUE) ## questionable?
  lambda <- ((n + 1) / n) %>%
    sqrt() %>%
    `*`(k)
  c(mu.hat - (lambda * sd.hat), mu.hat + (lambda * sd.hat))
}


##' Reports the maximum percentage beyond k * sqrt((n + 1)/n)
##' standard deviations from mean
##' @title Chebyshev Inequality with sample mean.
##' Utilizes Chebyshev inequality with sample mean.
##' @param n Sample size
##' @param k Number of standard deviations.
##' @return
##' @author Sangeeta Bhatia
chebyshev_ineq_sample <- function(n, k) {
  lambda <- k * sqrt((n + 1) / n)
  (((n + 1) * (n^2 - 1 + n * (lambda^2))) /
    (n^2 * lambda^2)) %>%
    floor() %>%
    `/`(n + 1)
}

##' For sample size n, what should k be so that the p% of the data
##' is outside k standard deviations of the sample mean.
##' @details if k=interval_width_for_p(n, p), then
##' chebyshev_ineq_sample(n, k) should be p.
##' @title Interval width for Chebysev Inequality with sample mean.
##' @param n
##' @param p
##' @return
##' @author Sangeeta Bhatia
interval_width_for_p <- function(n, p) {
  lower_lim <- (n^2 - 1) / ((p * n * (n + 1)) - 1)
  upper_lim <- (n^2 - 1) / ((p * n * (n + 1)) - 1 - n)
  return(c(lower_lim, upper_lim))
}
