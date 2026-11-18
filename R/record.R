#' The metadata record: YAML semantics and the rules the schema cannot express
#'
#' Rule R12 says header YAML must read the same under YAML 1.1 and YAML 1.2 core schema,
#' which is a statement about the *text*, not about whatever one library happens to
#' return - so the portable-scalar check runs on the text as written, before parsing (see
#' R/yaml-scan.R). R8 forbids duplicate mapping keys, anchors, aliases and merge keys; R13
#' forbids non-finite numbers. docs/SCHEMA-VERSIONS.md adds two requirements the contracts do not express:
#' required values must be non-empty, and `format` must be asserted. The first is a
#' warning (rejecting it would invalidate records the released schemas accept); the
#' second is enforced in [bh_validate()].
#'
#' @name record
NULL

#' R6 in the header text: characters YAML treats as line breaks.
#' @noRd
.bh_line_break_issues <- function(lines) {
  if (any(grepl("\u0085|\u2028|\u2029", lines, perl = TRUE))) {
    return("R6: a character YAML treats as a line break")
  }
  character()
}

#' R13: non-finite numbers in the parsed value, at any depth.
#'
#' A YAML `.nan`, `.inf` or `-.inf`, or a decimal too large for a double (`1.0e+400`),
#' arrives here as NaN or an infinity. The words `NaN` and `Infinity` written plain are
#' strings in YAML 1.1 and 1.2 alike, so they are text, not numbers, and pass.
#' @noRd
.bh_finite_issues <- function(record) {
  paths <- .bh_nonfinite_paths(record)
  if (!length(paths)) return(character())
  paste0("R13: ", paths, " is not a finite number")
}

.bh_nonfinite_paths <- function(x, path = "") {
  if (is.list(x)) {
    nms <- names(x)
    out <- character()
    for (i in seq_along(x)) {
      nm <- if (!is.null(nms) && nzchar(nms[[i]])) nms[[i]] else as.character(i - 1L)
      out <- c(out, .bh_nonfinite_paths(x[[i]], paste0(path, "/", nm)))
    }
    return(out)
  }
  if (is.double(x)) {
    bad <- which(is.nan(x) | is.infinite(x))
    if (!length(bad)) return(character())
    # R's yaml returns a sequence of numbers as one vector: name the items in it
    if (length(x) == 1L) return(if (nzchar(path)) path else "/")
    return(paste0(path, "/", bad - 1L))
  }
  character()
}

# Integers outside R's 32-bit range would otherwise read as NA with a warning, so a
# genome's `totalBasePairs: 3100000000` failed its contract and an extension value
# silently became the string "NA". They read as doubles instead, which are exact up to
# 2^53; larger integers keep their magnitude, as the nearest double.
.bh_yaml_int <- function(x) {
  v <- suppressWarnings(as.integer(x))
  if (!is.na(v)) v else as.numeric(x)
}

.bh_yaml_hex <- function(x) {
  neg <- startsWith(x, "-")
  d <- tolower(gsub("_", "", sub("^[-+]?0[xX]", "", x), fixed = TRUE))
  digits <- match(strsplit(d, "", fixed = TRUE)[[1L]], c(0:9, letters[1:6])) - 1
  v <- sum(digits * 16^(rev(seq_along(digits)) - 1))
  if (neg) v <- -v
  if (abs(v) <= .Machine$integer.max) as.integer(v) else v
}

# R's yaml returns NA for a decimal beyond the double range; YAML readers return an
# infinity, which rule R13 then rejects by name.
.bh_yaml_float <- function(x) as.numeric(x)

# R's yaml reads `.na`, `.na.real`, `.na.integer` and `.na.character` as R's NA. They are
# not YAML: both YAML versions read them as strings, and so does every other reader.
.bh_yaml_string <- function(x) x

.bh_yaml_handlers <- list(
  int = .bh_yaml_int, `int#hex` = .bh_yaml_hex,
  `float#fix` = .bh_yaml_float, `float#exp` = .bh_yaml_float,
  `bool#na` = .bh_yaml_string, `int#na` = .bh_yaml_string,
  `float#na` = .bh_yaml_string, `str#na` = .bh_yaml_string
)

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
#' The text is scanned first (R/yaml-scan.R). Text holding an anchor, alias, merge key or
#' tag is never handed to the parser: R's yaml expands aliases while parsing. Text over
#' the YAML reader limits is refused before the recursive parser can exhaust the C stack.
#'
#' @return A list with `record`, `why` (rejections) and `ok`.
#' @noRd
.bh_parse_record <- function(lines) {
  if (!length(lines)) {
    return(list(record = NULL, why = "R2: no header text to parse", ok = FALSE))
  }
  scan <- .bh_yaml_scan(lines)
  if (!is.null(scan$limit)) bh_abort("limit", "%s", scan$limit)
  why <- c(.bh_line_break_issues(lines), scan$why)
  if (!scan$safe) return(list(record = NULL, why = unique(why), ok = FALSE))
  txt <- paste(lines, collapse = "\n")
  rec <- tryCatch(
    yaml::yaml.load(txt, eval.expr = FALSE, handlers = .bh_yaml_handlers),
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
  why <- c(why, .bh_finite_issues(rec))
  list(record = rec, why = unique(why), ok = !length(why))
}
