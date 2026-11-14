#' Schema selection: rules V1 to V7 of docs/SCHEMA-VERSIONS.md
#'
#' A record names the schema it follows in its `schema` value and the version of that
#' contract in `schemaVersion`; a reader looks only at `schema` to decide which contract
#' to apply. The rules are exact-match URL patterns, and the outcomes differ in kind:
#'
#' * V1 raw-main selects this package's current copy of that type.
#' * V2/V3 a release tag or its w3id alias selects that release's copy, if held.
#' * V4 a ref that is neither `main` nor a held release, or a release with no contract of
#'   that type, is `unsupported-version`: the file is not checked against another schema,
#'   and the message names the value and the releases this tool has.
#' * V5 any other value is FHR against the current FHR schema - the behaviour FHR's
#'   unconstrained `schema` field has always had. This is where a made-up
#'   `…/fht/v0.7.0` URL lands: an unpublished type has no registry row, so no release
#'   number is invented for it and the lane never reads it as a draft.
#' * V6 raw-main plus the *number* 1 is an FHR 1 record, checked against v0.3.1's schema
#'   and warned about as deprecated, not invalid.
#' * V7 an unreleased draft, recognised only when the caller asked for the lane, read
#'   against the bytes this package was built with and warned about on every record.
#'
#' @name selection
NULL

.bh_raw_re <- paste0(
  "^https://raw\\.githubusercontent\\.com/FAIR-bioHeaders/",
  "(?:FHR|FAIR-bioHeaders)-Specification/([^/]+)/(fhr|fhp|fhgff3)\\.json$"
)
.bh_w3id_re <- "^https://w3id\\.org/fair-bioheaders/(fhr|fhp|fhgff3)/(v[0-9]+\\.[0-9]+\\.[0-9]+)/?$"
.bh_types_by_file <- c(fhr = "FHR", fhp = "FHP", fhgff3 = "FHGFF3")

#' Chooses the contract for a `schema` value.
#'
#' @param value The record's `schema` value.
#' @param schema_version The record's `schemaVersion`, when known (rule V6 needs it).
#' @param draft Draft-lane request: `FALSE` (default) or a character vector of draft
#'   types to recognise, for example `"FHT"`. Only the raw-main URL of the development
#'   repository that owns the type is in the lane.
#' @return A list with `rule`, `header_type`, `release`, `file`, `schema_version`,
#'   `status` (`released`, `fhr1`, `draft` or `unsupported`), `message` and `warnings`.
#' @export
bh_select <- function(value, schema_version = NULL, draft = FALSE) {
  reg <- .bh_registry()
  lane <- .bh_lane_types(draft)

  pick <- function(type, release, rule) {
    v <- reg$releases[[release]][[.bh_type_name(type)]]
    if (is.null(v)) {
      return(.bh_unsupported(value, .bh_type_name(type), rule,
        paste0(.bh_type_name(type), ": unsupported schema version: ", value,
               " (release ", release, " registers no contract of this type; this tool has ",
               .bh_type_name(type), " schemas for ",
               paste(bh_releases(.bh_type_name(type)), collapse = ", "), ")")))
    }
    row <- .bh_contract_row(.bh_type_name(type), v)
    if (is.null(row)) {
      return(.bh_unsupported(value, .bh_type_name(type), rule,
        paste0(.bh_type_name(type), ": unsupported schema version: ", value,
               " (this tool has ", .bh_type_name(type), " schemas for ",
               paste(bh_releases(.bh_type_name(type)), collapse = ", "), ")")))
    }
    list(
      rule = rule, header_type = .bh_type_name(type), release = release,
      file = .bh_inst("schemas", row$file), schema_version = as.character(v),
      status = "released", message = NA_character_, warnings = character()
    )
  }

  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    return(pick("fhr", reg$current, "V5"))
  }

  m <- regmatches(value, regexec(.bh_raw_re, value))[[1L]]
  if (length(m)) {
    ref <- m[[2L]]
    file <- m[[3L]]
    if (ref == "main") {
      # V6 before V1: raw-main plus the number 1 is an FHR 1 record, not a current one
      if (file == "fhr" && .bh_is_number_one(schema_version)) {
        row <- .bh_contract_row("FHR", "1")
        if (is.null(row)) {
          return(.bh_unsupported(value, "FHR", "V6",
            "FHR: the v0.3.1 contract this FHR 1 record needs is not bundled"))
        }
        return(structure(list(
          rule = "V6", header_type = "FHR", release = "v0.3.1",
          file = .bh_inst("schemas", row$file), schema_version = "1",
          status = "fhr1", message = NA_character_,
          warnings = paste0(
            "FHR: warning: schemaVersion 1 via the raw-main schema URL is read as ",
            "FHR 1 (v0.3.1); cite https://w3id.org/fair-bioheaders/fhr/v0.3.1 or move ",
            "to schemaVersion \"2.0\""
          )
        ), class = "bh_selection"))
      }
      return(pick(file, reg$current, "V1"))
    }
    if (grepl("^v[0-9]+\\.[0-9]+\\.[0-9]+$", ref)) {
      if (!ref %in% names(reg$releases)) {
        return(.bh_unsupported(value, .bh_type_name(file), "V4",
          paste0(.bh_type_name(file),
                 ": unsupported schema version: ", value, " (this tool has ",
                 .bh_type_name(file), " schemas for ",
                 paste(bh_releases(.bh_type_name(file)), collapse = ", "), ")")))
      }
      return(pick(file, ref, "V2"))
    }
    return(.bh_unsupported(value, .bh_type_name(file), "V4",
      paste0(.bh_type_name(file),
             ": unsupported schema version: ", value, " (this tool has ",
             .bh_type_name(file), " schemas for ",
             paste(bh_releases(.bh_type_name(file)), collapse = ", "), ")")))
  }

  m <- regmatches(value, regexec(.bh_w3id_re, value))[[1L]]
  if (length(m)) {
    type <- m[[2L]]
    release <- m[[3L]]
    if (!release %in% names(reg$releases)) {
      return(.bh_unsupported(value, .bh_type_name(type), "V4",
        paste0(.bh_type_name(type),
               ": unsupported schema version: ", value, " (this tool has ",
               .bh_type_name(type), " schemas for ",
               paste(bh_releases(.bh_type_name(type)), collapse = ", "), ")")))
    }
    return(pick(type, release, "V3"))
  }

  # V7: only a raw-main URL of the development repository that owns a draft type, and
  # only when the caller asked for the lane.
  for (t in names(lane)) {
    if (isTRUE(lane[[t]]) && identical(value, .bh_draft_citation(t))) {
      return(.bh_draft_selection(t, value))
    }
  }

  # V5
  pick("fhr", reg$current, "V5")
}

.bh_type_name <- function(x) {
  if (is.na(x)) return(NA_character_)
  .bh_types_by_file[[as.character(x)]]
}

.bh_is_number_one <- function(v) {
  is.numeric(v) && length(v) == 1L && !is.na(v) && v == 1
}

.bh_unsupported <- function(value, type, rule, message) {
  structure(list(
    rule = rule, header_type = type,
    release = NA_character_, file = NA_character_, schema_version = NA_character_,
    status = "unsupported", message = message, warnings = character()
  ), class = "bh_selection")
}

print.bh_selection <- function(x, ...) {
  cat("<bh_selection ", if (is.na(x$header_type)) "?" else x$header_type,
      " ", x$release %||% NA_character_, " rule ", x$rule, " ", x$status, ">\n", sep = "")
  if (!is.null(x$message) && !is.na(x$message)) cat("  ", x$message, "\n", sep = "")
  invisible(x)
}
