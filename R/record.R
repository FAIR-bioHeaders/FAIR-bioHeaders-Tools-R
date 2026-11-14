#' The metadata record: YAML semantics and the rules the schema cannot express
#'
#' Rule R12 says header YAML must read the same under YAML 1.1 and YAML 1.2 core schema,
#' which is a statement about the *text*, not about whatever one library happens to
#' return - so the portable-scalar check runs on the lines as written. R8 forbids
#' duplicate mapping keys, anchors, aliases and merge keys; R13 forbids non-finite
#' numbers. docs/SCHEMA-VERSIONS.md adds two requirements the contracts do not express:
#' required values must be non-empty, and `format` must be asserted. The first is a
#' warning (rejecting it would invalidate records the released schemas accept); the
#' second is enforced in [bh_validate()].
#'
#' @name record
NULL

#' R8 in text: anchors, aliases and merge keys.
#' @noRd
.bh_yaml_structural_issues <- function(lines) {
  why <- character()
  for (l in lines) {
    body0 <- sub("^[ \t]*", "", l)
    body <- sub("^[ \t]*-[ \t]*", "", body0)
    val <- if (grepl(":", body)) trimws(sub("^[^:#]*:[ \t]*", "", body)) else trimws(body)
    key <- trimws(sub("([ \t]*):.*$", "", body))
    if (identical(key, "<<")) why <- c(why, "R8: a merge key")
    if (grepl("^&[A-Za-z0-9_-]", val)) why <- c(why, "R8: an anchor")
    if (grepl("^\\*[A-Za-z0-9_-]", val) || grepl("^[ \t]*-[ \t]*\\*[A-Za-z0-9_-]", l)) {
      why <- c(why, "R8: an alias")
    }
    if (grepl("^!!", val) || grepl("(^|[ \t])!![A-Za-z]", val)) {
      why <- c(why, "R12: an explicit YAML tag")
    }
    if (grepl("\u0085|\u2028|\u2029", l, perl = TRUE)) {
      why <- c(why, "R6: a character YAML treats as a line break")
    }
  }
  unique(why)
}

#' R12: plain scalars whose YAML 1.1 and YAML 1.2 readings differ.
#' @noRd
.bh_yaml_scalar_issues <- function(lines) {
  why <- character()
  for (l in lines) {
    body0 <- sub("^[ \t]*", "", l)
    body <- sub("^[ \t]*-[ \t]*", "", body0)
    if (!grepl(":", body)) next
    val <- trimws(sub("^[^:#]*:[ \t]*", "", body))
    if (!.bh_plain_value(val)) next
    bad <- NULL
    if (grepl("^0[0-7]+$", val)) bad <- "a leading-zero integer, octal in YAML 1.1"
    if (grepl("^[0-9][0-9_]*_[0-9_]+$", val)) bad <- "an underscored number"
    if (grepl("^0[bx][0-9A-Fa-f_]+$", val)) bad <- "a binary or octal or hexadecimal literal"
    if (grepl("^[+-]?[0-9]+:[0-9]", val)) bad <- "a sexagesimal number"
    # R12 names these specifically: the YAML 1.1 boolean words that YAML 1.2 core
    # schema reads as strings. `true` and `false` are booleans in both versions, so
    # they are portable and must not be rejected here - the valid vector
    # fhp-fasta-extension-fields carries `reviewed: true`.
    if (tolower(val) %in% c("y", "n", "yes", "no", "on", "off")) {
      bad <- "a YAML 1.1 boolean word, which YAML 1.2 core schema reads as a string"
    }
    if (grepl("^[+-]?[0-9]+[eE][+-]?[0-9]+$", val)) bad <- "an exponent without a decimal point"
    if (!is.null(bad)) {
      why <- c(why, paste0("R12: ", bad, " written plain: ", val))
    }
  }
  unique(why)
}

#' R13: non-finite numbers, in the text and in the parsed value.
#' @noRd
.bh_finite_issues <- function(lines, record) {
  why <- character()
  for (l in lines) {
    if (grepl("(^|[ \t:])-?\\.inf([ \t]|$)", l) || grepl("(^|[ \t:])\\.nan([ \t]|$)", l)) {
      why <- c(why, "R13: a YAML .inf/.nan value")
    }
    if (grepl("(^|[^A-Za-z0-9_])(NaN|Infinity)([^A-Za-z0-9_]|$)", l)) {
      why <- c(why, "R13: a JSON-extension NaN or Infinity")
    }
  }
  if (length(.bh_nonfinite_paths(record))) {
    why <- c(why, "R13: a value that is not a finite number")
  }
  unique(why)
}

.bh_nonfinite_paths <- function(x, path = "") {
  if (is.list(x)) {
    out <- character()
    for (nm in names(x)) {
      out <- c(out, .bh_nonfinite_paths(x[[nm]], paste0(path, "/", nm)))
    }
    return(out)
  }
  if (is.numeric(x) && length(x) == 1L && !is.na(x) && !is.finite(x)) return(path)
  character()
}

#' R8 structural check: duplicate mapping keys at the same level.
#'
#' @param lines The header lines with their prefix removed.
#' @return TRUE when a mapping key repeats inside one scope.
#' @noRd
.bh_duplicate_keys <- function(lines) {
  levels <- list()
  for (l in lines) {
    if (!nzchar(trimws(l)) || startsWith(trimws(l), "#")) next
    # regexpr, not sub(): the POSIX sub() back-reference returns the wrong width in R
    lead <- nchar(regmatches(l, regexpr("^ *", l)))
    item <- grepl("^[ \t]*-[ \t]", l)
    body <- sub("^[ \t]*-[ \t]*", "", l)
    if (item) {
      while (length(levels) && levels[[length(levels)]]$ind > lead) {
        levels[length(levels)] <- NULL
      }
    }
    m <- regmatches(body, regexec("^([^:#]+?):([ \t]|$)", body))[[1L]]
    if (!length(m)) next
    ind <- lead + if (item) 2L else 0L
    key <- trimws(m[[2L]])
    while (length(levels) && levels[[length(levels)]]$ind > ind) {
      levels[length(levels)] <- NULL
    }
    if (!length(levels) || levels[[length(levels)]]$ind < ind) {
      levels[[length(levels) + 1L]] <- list(ind = ind, keys = character())
    }
    top <- length(levels)
    if (key %in% levels[[top]]$keys) return(TRUE)
    levels[[top]]$keys <- c(levels[[top]]$keys, key)
  }
  FALSE
}

#' SCHEMA-VERSIONS.md, "required values are non-empty": warn, do not reject.
#' @noRd
.bh_empty_required_warnings <- function(record, contract) {
  req <- contract$required
  out <- character()
  for (f in req) {
    v <- record[[f]]
    if (is.null(v)) {
      out <- c(out, paste0("empty-required: ", f, " is missing"))
      next
    }
    if (is.character(v) && length(v) == 1L && !nzchar(v)) {
      out <- c(out, paste0("empty-required: ", f, " is an empty string"))
    } else if (is.list(v) && !length(v)) {
      out <- c(out, paste0("empty-required: ", f, " has no value"))
    } else if (is.list(v) && !is.null(dim(v))) {
      next
    } else if (is.list(v)) {
      for (it in v) {
        if (is.list(it) && !length(it)) {
          out <- c(out, paste0("empty-required: ", f, " holds an empty item"))
          break
        }
        if (is.list(it) && length(it) == 1L && !nzchar(.bh_c(it$name, "x"))) {
          out <- c(out, paste0("empty-required: ", f, " holds an item with an empty name"))
          break
        }
        if (is.character(it) && !nzchar(it)) {
          out <- c(out, paste0("empty-required: ", f, " holds an empty string"))
          break
        }
      }
    }
  }
  if (!is.null(record$taxon)) {
    t <- record$taxon
    if (!nzchar(.bh_c(t$name, "")) && !nzchar(.bh_c(t$uri, ""))) {
      out <- c(out, "empty-required: taxon has neither name nor uri")
    }
  }
  unique(out)
}

#' Parses the header text into a record.
#'
#' @return A list with `record`, `why` (rejections) and `ok`.
#' @noRd
.bh_parse_record <- function(lines) {
  if (!length(lines)) {
    return(list(record = NULL, why = "R2: no header text to parse", ok = FALSE))
  }
  why <- c(.bh_yaml_structural_issues(lines), .bh_yaml_scalar_issues(lines))
  txt <- paste(lines, collapse = "\n")
  rec <- tryCatch(
    yaml::yaml.load(txt, eval.expr = FALSE),
    error = function(e) {
      msg <- conditionMessage(e)
      why <<- c(why, if (grepl("[Dd]uplicate", msg)) {
        "R8: a duplicate mapping key"
      } else {
        paste0("the header YAML does not parse: ", msg)
      })
      NULL
    }
  )
  if (is.null(rec)) return(list(record = NULL, why = unique(why), ok = FALSE))
  if (!is.list(rec)) {
    return(list(record = NULL, why = "the header YAML is not a mapping", ok = FALSE))
  }
  # R's yaml collapses a one-item sequence to an atomic vector, which then fails a
  # `type: array` property the file does satisfy. The shape is read back off the text; see
  # R/yaml-shape.R for why it is not read back off the contract.
  rec <- .bh_repair_shape(rec, .bh_sequence_keys(lines))
  if (.bh_duplicate_keys(lines)) why <- c(why, "R8: a duplicate mapping key")
  why <- c(why, .bh_finite_issues(lines, rec))
  list(record = rec, why = unique(why), ok = !length(why))
}
