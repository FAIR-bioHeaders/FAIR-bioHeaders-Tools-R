#' Header YAML, scanned before it is parsed
#'
#' Rules R8 and R12 are statements about the text as written: no anchors, aliases, merge
#' keys or tags anywhere, and no plain scalar that YAML 1.1 and YAML 1.2 read differently.
#' A check that looks only at the start of a `key: value` line misses the same constructs
#' inside flow collections (`[&a x, *a]`, `{k: on}`), on keys, and after a sequence dash.
#' Worse, R's `yaml` package expands aliases while it parses, so an alias that gets past the
#' check is expanded in memory before any rule runs: nine nested levels of ten aliases each
#' is the classic "billion laughs" input, and the parser runs out of memory on it.
#'
#' So the header text is tokenized here first, quote-aware and comment-aware, and the
#' parser only ever sees text that has none of those constructs. The scanner knows the
#' structure YAML gives the text - block mappings and sequences by indentation, flow
#' collections by brackets, quoted scalars that span lines, block scalars whose bodies are
#' opaque text - so it can also
#'
#' * type every plain scalar, key or value, block or flow, under both YAML versions, using
#'   the same resolvers as the Python reference (YAML 1.2 core schema; YAML 1.1 as PyYAML
#'   resolves it, plus `y` and `n`), and reject the ones that disagree (R12);
#' * reject a mapping key that is not a string (`{1: x}`, `{~: x}`, `{[a]: b}`): the
#'   metadata is JSON-shaped, and JSON object keys are strings;
#' * find duplicate keys per mapping, block or flow (R8), without being fooled by text inside
#'   a block scalar or a quoted value; and
#' * enforce the reader limits of docs/FORMAT.md on YAML metadata - more than 20,000 nodes,
#'   or nesting more than 64 levels deep - before the recursive parser can exhaust the C
#'   stack.
#'
#' This is a tokenizer, not a parser: it does not build values (`yaml::yaml.load()` still
#' does that), and text it cannot make sense of is left for the parser to reject.
#'
#' @name yaml-scan
#' @keywords internal
NULL

# docs/FORMAT.md: "Readers may refuse input beyond these limits ... YAML metadata with more
# than 20,000 nodes or nested more than 64 levels deep". A node is any scalar, sequence or
# mapping, keys included; the root collection is level 1.
.bh_yaml_limits <- list(nodes = 20000L, depth = 64L)

# The first characters any non-string reading can start with, under either YAML version:
# null (~ n N, or empty), booleans (y Y n N t T f F o O), numbers (- + . digits), the
# merge key (<) and the YAML 1.1 value key (=). Anything else is a string in both.
.bh_typed_start <- "^[-+.0-9~nNyYtTfFoO<=]"

# A block line holding `key: value` with a plain key and a plain value that needs no
# tokenizing: no quote, comment, flow, block-scalar, property or alias character, and no
# second ": ". Groups: indentation, key, value (possibly empty).
.bh_simple_line <- paste0(
  "^( *)([A-Za-z0-9_][A-Za-z0-9_.-]*):",
  "(?:[ ]+((?![-?:](?: |$))[^ #'\"\\[\\]{}&*!|>%@`,](?:(?!: )[^#\\[\\]{}])*?))?[ ]*$"
)

# Flow-context tokens, in priority order: blanks, a comment, an indicator, a quoted scalar
# (closed, or running to the end of the line), a property or alias, a plain scalar.
.bh_flow_token <- paste0(
  "[ \t]+|#.*$|[,\\[\\]{}]|:(?=[ \t,\\[\\]{}]|$)|\\?(?=[ \t]|$)",
  "|\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^']|'')*'|[\"'].*$",
  "|[&!*][^ \t,\\[\\]{}]*",
  "|(?:[^,\\[\\]{}:#]|:(?![ \t,\\[\\]{}]|$)|(?<![ \t])#)+"
)

#' The YAML 1.2 core-schema type of a plain scalar.
#' @noRd
.bh_tag12 <- function(v) {
  if (grepl("^(?:~|null|Null|NULL|)$", v, perl = TRUE)) return("null")
  if (grepl("^(?:true|True|TRUE|false|False|FALSE)$", v, perl = TRUE)) return("bool")
  if (grepl("^(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$", v, perl = TRUE)) return("int")
  if (grepl(paste0(
    "^(?:[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?",
    "|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$"
  ), v, perl = TRUE)) {
    return("float")
  }
  "str"
}

#' The YAML 1.1 type of a plain scalar, as PyYAML's resolver gives it plus `y`/`n`.
#'
#' Resolver order matters where two patterns could both match: bool, float, int, merge,
#' null, timestamp, value. Timestamps count as strings: R12 keeps dates as written.
#' @noRd
.bh_tag11 <- function(v) {
  if (v %in% c("y", "Y", "n", "N")) return("bool")
  if (grepl(paste0(
    "^(?:yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE",
    "|on|On|ON|off|Off|OFF)$"
  ), v, perl = TRUE)) {
    return("bool")
  }
  if (grepl(paste0(
    "^(?:[-+]?(?:[0-9][0-9_]*)\\.[0-9_]*(?:[eE][-+][0-9]+)?",
    "|\\.[0-9_]+(?:[eE][-+][0-9]+)?",
    "|[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\\.[0-9_]*",
    "|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$"
  ), v, perl = TRUE)) {
    return("float")
  }
  if (grepl(paste0(
    "^(?:[-+]?0b[0-1_]+|[-+]?0[0-7_]+|[-+]?(?:0|[1-9][0-9_]*)",
    "|[-+]?0x[0-9a-fA-F_]+|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$"
  ), v, perl = TRUE)) {
    return("int")
  }
  if (identical(v, "<<")) return("merge")
  if (grepl("^(?:~|null|Null|NULL|)$", v, perl = TRUE)) return("null")
  if (identical(v, "=")) return("value")
  "str"
}

#' The type both YAML versions give a plain scalar, or NA when they disagree (rule R12).
#' @noRd
.bh_portable_tag <- function(v) {
  if (nzchar(v) && !grepl(.bh_typed_start, v, perl = TRUE)) return("str")
  t <- .bh_tag12(v)
  if (!identical(t, .bh_tag11(v))) return(NA_character_)
  if (identical(t, "int")) {
    d <- sub("^[-+]", "", v)
    # YAML 1.1 reads a leading zero as octal
    if (nchar(d) > 1L && substr(d, 1L, 1L) == "0" && !substr(d, 2L, 2L) %in% c("x", "X")) {
      return(NA_character_)
    }
  }
  t
}

#' Scans header YAML for what rules R8 and R12 forbid, and for the reader limits.
#'
#' @param lines The header lines with their prefix removed.
#' @return A list with `why` (rejections, rule-labelled), `safe` (FALSE when the text holds
#'   an anchor, alias, merge key or tag, which the parser must then never see), and
#'   `limit` (NULL, or the message naming the reader limit the text exceeds).
#' @noRd
.bh_yaml_scan <- function(lines) {
  lim <- .bh_yaml_limits
  why <- character()
  unsafe <- FALSE
  limit <- NULL
  nodes <- 0L
  blk <- list()     # open block collections: list(ind, kind, level, keys)
  flow <- list()    # open flow collections: list(kind, level, expect_key, keys)
  pending <- NULL   # a key or dash whose value has not started: list(ind, level)
  plain <- NULL     # an open multi-line block plain scalar: list(ind, level, text)
  quote <- NULL     # a quoted scalar continuing on the next line: list(ch, flow)
  bscalar <- NULL   # an open block scalar body: list(parent, ind)

  flag <- function(msg, structural = FALSE) {
    why <<- c(why, msg)
    if (structural) unsafe <<- TRUE
  }
  halted <- function() !is.null(limit)
  node <- function(level) {
    nodes <<- nodes + 1L
    if (is.null(limit) && nodes > lim$nodes) {
      limit <<- paste0("the header YAML holds more than ", lim$nodes,
        " nodes, over the limit docs/FORMAT.md allows a reader to enforce")
    }
    if (is.null(limit) && level > lim$depth) {
      limit <<- paste0("the header YAML is nested more than ", lim$depth,
        " levels deep, over the limit docs/FORMAT.md allows a reader to enforce")
    }
  }
  new_keys <- function() new.env(hash = TRUE, parent = emptyenv())
  add_key <- function(keys, k) {
    if (is.null(keys)) return(invisible())
    # hex of the UTF-8 bytes: environment names pass through the native encoding, where
    # two different non-ASCII keys could collide (or warn) under a C locale
    id <- paste0("k", paste(as.character(charToRaw(enc2utf8(k))), collapse = ""))
    if (exists(id, envir = keys, inherits = FALSE)) {
      flag("R8: a duplicate mapping key")
    } else {
      assign(id, TRUE, envir = keys)
    }
  }
  check_plain <- function(text, level, key = FALSE, keys = NULL) {
    node(level)
    if (identical(text, "<<")) {
      flag(if (key) "R8: a merge key" else "R8: a plain `<<`, which YAML 1.1 reads as a merge key",
        structural = TRUE)
      return(invisible())
    }
    t <- .bh_portable_tag(text)
    if (is.na(t)) {
      flag(paste0("R12: the plain value ", text,
        " is read differently by YAML 1.1 and YAML 1.2; quote it"))
    } else if (key && !identical(t, "str")) {
      flag(paste0("R8: the mapping key ", if (nzchar(text)) text else "(empty)",
        " is not a string"))
    }
    if (key) add_key(keys, text)
  }
  quoted_key <- function(raw, ch, keys) {
    body <- substr(raw, 2L, nchar(raw) - 1L)
    add_key(keys, if (ch == "'") gsub("''", "'", body, fixed = TRUE) else body)
  }
  # The end of a quoted scalar opened at `p` (the quote itself), or NA when it continues
  # past the end of the line.
  quote_end <- function(l, p, ch) {
    rest <- substr(l, p + 1L, .bhc_max)
    pat <- if (ch == "\"") "^(?:[^\"\\\\]|\\\\.)*\"" else "^(?:[^']|'')*'"
    m <- regexpr(pat, rest, perl = TRUE)
    if (m < 0L) NA_integer_ else p + attr(m, "match.length")
  }
  property_end <- function(l, p) {
    rest <- substr(l, p, .bhc_max)
    p + attr(regexpr("^[^ \t,\\[\\]{}]*", rest, perl = TRUE), "match.length")
  }
  # Properties (anchor &, tag !) and aliases (*) at a token start.
  property <- function(l, p) {
    ch <- substr(l, p, p)
    rest <- substr(l, p, .bhc_max)
    tok <- regmatches(rest, regexpr("^[^ \t,\\[\\]{}]*", rest, perl = TRUE))
    if (ch == "&") flag("R8: an anchor", structural = TRUE)
    if (ch == "*") flag("R8: an alias", structural = TRUE)
    if (ch == "!") flag(paste0("R12: an explicit YAML tag ", tok), structural = TRUE)
    p + nchar(tok)
  }
  skip_ws <- function(l, p) {
    m <- regexpr("^[ \t]*", substr(l, p, .bhc_max))
    p + attr(m, "match.length")
  }
  at_end <- function(l, p) p > nchar(l) || substr(l, p, p) == "#"
  # A plain key at `p`: the text before the first ": " (or ":" at the end of the line) that
  # comes before any " #" comment. NULL when the line holds no such key.
  plain_key <- function(l, p) {
    rest <- substr(l, p, .bhc_max)
    if (grepl("^[\\[\\]{},\"'|>%@`#]", rest, perl = TRUE)) return(NULL)
    m <- regexpr("^(?:[^:#]|:(?![ \t]|$)|(?<![ \t])#)*?(?=[ \t]*:(?:[ \t]|$))", rest, perl = TRUE)
    if (m < 0L) return(NULL)
    text <- sub("[ \t]+$", "", substr(rest, 1L, attr(m, "match.length")))
    colon <- regexpr(":(?:[ \t]|$)", substr(rest, attr(m, "match.length") + 1L, .bhc_max), perl = TRUE)
    list(text = text, after = p + attr(m, "match.length") + colon)
  }
  # Whether a block line's content at `p` starts a mapping entry.
  key_line <- function(l, p) {
    while (substr(l, p, p) %in% c("&", "!")) p <- skip_ws(l, property_end(l, p))
    rest <- substr(l, p, .bhc_max)
    grepl("^[?:](?:[ \t]|$)", rest, perl = TRUE) ||
      grepl("^(?:\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^']|'')*')[ \t]*:(?:[ \t]|$)", rest, perl = TRUE) ||
      !is.null(plain_key(l, p))
  }
  finish_plain <- function() {
    if (!is.null(plain)) {
      check_plain(plain$text, plain$level)
      plain <<- NULL
    }
  }
  # Flow context: scan from `p` to the end of the line, or until the outermost flow
  # collection closes (then the rest of the line is block context again).
  flow_scan <- function(l, p) {
    # One pass over the rest of the line: a header line can be a single 300 KB flow value,
    # so the tokens are found by one regular expression rather than by re-reading the line.
    rest <- substr(l, p, .bhc_max)
    tok <- regmatches(rest, gregexpr(.bh_flow_token, rest, perl = TRUE))[[1L]]
    n <- length(tok)
    i <- 0L
    nonblank <- function(j) {
      while (j <= n && grepl("^[ \t]", tok[[j]], perl = TRUE)) j <- j + 1L
      if (j <= n) tok[[j]] else ""
    }
    json_prev <- FALSE # the previous token was a quoted scalar or a closed collection
    while (length(flow) && !halted() && i < n) {
      i <- i + 1L
      t <- tok[[i]]
      ch <- substr(t, 1L, 1L)
      if (ch == " " || ch == "\t") next
      # After a JSON-like node, ":" is the value indicator even with no space after it
      # (`{"count":4}`): split it off the plain text the tokenizer read it into.
      if (json_prev && ch == ":" && nchar(t) > 1L) {
        flow[[length(flow)]]$expect_key <<- FALSE
        t <- substr(t, 2L, nchar(t))
        if (grepl("^[ \t]", t, perl = TRUE)) t <- sub("^[ \t]+", "", t)
        ch <- substr(t, 1L, 1L)
        if (!nzchar(t)) next
      }
      json_prev <- ch %in% c("\"", "'", "]", "}")
      if (ch == "#") return(invisible())
      top <- length(flow)
      fr <- flow[[top]]
      if (t == ",") {
        flow[[top]]$expect_key <<- identical(fr$kind, "{")
        next
      }
      if (t == "]" || t == "}") {
        flow[[top]] <<- NULL
        if (!length(flow) && startsWith(nonblank(i + 1L), ":")) {
          flag("R8: a mapping key that is a collection, not a string")
        }
        next
      }
      if (t == ":") {
        flow[[top]]$expect_key <<- FALSE
        next
      }
      if (t == "?") next
      level <- fr$level + 1L
      is_key <- identical(fr$kind, "{") && isTRUE(fr$expect_key)
      if (ch %in% c("&", "!", "*")) {
        if (ch == "*") node(level)
        property(t, 1L)
        next
      }
      if (t == "[" || t == "{") {
        node(level)
        if (is_key) flag("R8: a mapping key that is a collection, not a string")
        flow[[top + 1L]] <<- list(kind = t, level = level, expect_key = t == "{",
          keys = if (t == "{") new_keys() else NULL)
        next
      }
      if (ch == "\"" || ch == "'") {
        node(level)
        if (is.na(quote_end(t, 1L, ch))) {
          quote <<- list(ch = ch, flow = TRUE)
          return(invisible())
        }
        if (is_key) quoted_key(t, ch, fr$keys)
        next
      }
      text <- sub("[ \t]+$", "", t)
      check_plain(text, level, key = is_key || nonblank(i + 1L) == ":",
        keys = if (is_key) fr$keys else NULL)
    }
  }
  # A value starting at `p` in block context, at node level `level`, owned by the block
  # collection whose indentation is `owner`.
  block_value <- function(l, p, level, owner) {
    repeat {
      ch <- substr(l, p, p)
      if (!ch %in% c("&", "!", "*")) break
      if (ch == "*") {
        node(level)
        property(l, p)
        return(invisible())
      }
      p <- skip_ws(l, property(l, p))
    }
    if (at_end(l, p)) {
      pending <<- list(ind = owner, level = level)
      return(invisible())
    }
    ch <- substr(l, p, p)
    if (ch == "\"" || ch == "'") {
      node(level)
      if (is.na(quote_end(l, p, ch))) quote <<- list(ch = ch, flow = FALSE)
      return(invisible())
    }
    if (ch == "[" || ch == "{") {
      node(level)
      flow[[1L]] <<- list(kind = ch, level = level, expect_key = ch == "{",
        keys = if (ch == "{") new_keys() else NULL)
      flow_scan(l, p + 1L)
      return(invisible())
    }
    if (ch == "|" || ch == ">") {
      node(level)
      bscalar <<- list(parent = owner, ind = NA_integer_)
      return(invisible())
    }
    text <- sub("[ \t]+$", "", sub("[ \t]#.*$", "", substr(l, p, .bhc_max)))
    plain <<- list(ind = owner, level = level, text = text)
  }
  # The content of a block line from `p`, inside the block collection `fi` (an index into
  # `blk`).
  block_content <- function(l, p, fi) {
    fr <- blk[[fi]]
    level <- fr$level + 1L
    if (fr$kind == "seq") {
      p <- skip_ws(l, p + 1L)
      if (at_end(l, p)) {
        pending <<- list(ind = fr$ind, level = level)
        return(invisible())
      }
      col <- p - 1L
      if (grepl("^-(?:[ \t]|$)", substr(l, p, .bhc_max), perl = TRUE)) {
        node(level)
        blk[[fi + 1L]] <<- list(ind = col, kind = "seq", level = level, keys = NULL)
        return(block_content(l, p, fi + 1L))
      }
      if (!is.null(plain_key(l, p)) || grepl("^[\"'][^\"']*[\"'][ \t]*:(?:[ \t]|$)", substr(l, p, .bhc_max), perl = TRUE)) {
        node(level)
        blk[[fi + 1L]] <<- list(ind = col, kind = "map", level = level, keys = new_keys())
        return(block_content(l, p, fi + 1L))
      }
      return(block_value(l, p, level, fr$ind))
    }
    # a mapping entry: [properties] key ":" value
    while (substr(l, p, p) %in% c("&", "!")) p <- skip_ws(l, property(l, p))
    ch <- substr(l, p, p)
    if (ch == "?" && grepl("^\\?(?:[ \t]|$)", substr(l, p, .bhc_max), perl = TRUE)) {
      return(block_value(l, skip_ws(l, p + 1L), level, fr$ind))
    }
    if (ch == ":" && grepl("^:(?:[ \t]|$)", substr(l, p, .bhc_max), perl = TRUE)) {
      return(block_value(l, skip_ws(l, p + 1L), level, fr$ind))
    }
    if (ch == "\"" || ch == "'") {
      e <- quote_end(l, p, ch)
      if (!is.na(e)) {
        q <- skip_ws(l, e + 1L)
        if (grepl("^:(?:[ \t]|$)", substr(l, q, .bhc_max), perl = TRUE)) {
          node(level)
          quoted_key(substr(l, p, e), ch, fr$keys)
          return(block_value(l, skip_ws(l, q + 1L), level, fr$ind))
        }
      }
      return(block_value(l, p, level, fr$ind))
    }
    if (ch == "*") {
      return(block_value(l, p, level, fr$ind))
    }
    k <- plain_key(l, p)
    if (is.null(k)) return(block_value(l, p, level, fr$ind))
    check_plain(k$text, level, key = TRUE, keys = fr$keys)
    block_value(l, skip_ws(l, k$after), level, fr$ind)
  }

  # Most header lines are `key: plain value`. Those are recognised once, vectorized, so the
  # loop below can skip the general tokenizer for them.
  simple <- regmatches(lines, regexec(.bh_simple_line, lines, perl = TRUE))
  blank_v <- grepl("^[ \t]*$", lines, perl = TRUE)
  ind_v <- attr(regexpr("^ *", lines), "match.length")
  dash_v <- grepl("^ *-(?:[ \t]|$)", lines, perl = TRUE)
  first_v <- substr(lines, ind_v + 1L, ind_v + 1L)
  marker_v <- grepl("^(?:---|\\.\\.\\.)(?:[ \t]|$)|^%", lines, perl = TRUE)

  for (li in seq_along(lines)) {
    l <- lines[[li]]
    if (halted()) break
    # inside a block scalar body: opaque text, ended by a less-indented non-blank line
    if (!is.null(bscalar)) {
      if (blank_v[[li]]) next
      ind <- ind_v[[li]]
      if (is.na(bscalar$ind) && ind > bscalar$parent) {
        bscalar$ind <- ind
        next
      }
      if (!is.na(bscalar$ind) && ind >= bscalar$ind) next
      bscalar <- NULL
    }
    p <- 1L
    if (!is.null(quote)) {
      e <- quote_end(paste0(quote$ch, l), 1L, quote$ch)
      if (is.na(e)) next
      inflow <- quote$flow
      quote <- NULL
      p <- e # the position just past the closing quote, in `l`
      if (inflow) {
        flow_scan(l, p)
      }
      next
    }
    if (length(flow)) {
      flow_scan(l, 1L)
      next
    }
    if (blank_v[[li]]) next
    ind <- ind_v[[li]]
    if (first_v[[li]] == "#") {
      finish_plain()
      next
    }
    if (marker_v[[li]]) {
      if (grepl("^%|^---(?:[ \t]|$)", l, perl = TRUE))
        flag("R12: YAML directives and document-start markers are forbidden", structural = TRUE)
      finish_plain()
      next
    }
    if (!is.null(plain) && ind > plain$ind) {
      more <- sub("[ \t]+$", "", sub("(^|[ \t])#.*$", "", substr(l, ind + 1L, .bhc_max)))
      if (nzchar(more)) plain$text <- paste(plain$text, more)
      next
    }
    finish_plain()

    dash <- dash_v[[li]]
    while (length(blk) && blk[[length(blk)]]$ind > ind) blk[[length(blk)]] <- NULL
    if (length(blk) && blk[[length(blk)]]$ind == ind &&
        blk[[length(blk)]]$kind == "seq" && !dash) {
      blk[[length(blk)]] <- NULL
    }
    kind <- if (dash) "seq" else "map"
    top <- length(blk)
    opens <- !is.null(pending) && (ind > pending$ind ||
      (dash && ind == pending$ind && top && blk[[top]]$kind == "map"))
    if (opens && !dash && !key_line(l, ind + 1L)) {
      # the pending value is a scalar or a flow collection written on its own line
      level <- pending$level
      owner <- pending$ind
      pending <- NULL
      block_value(l, ind + 1L, level, owner)
      next
    }
    if (opens) {
      level <- pending$level
      pending <- NULL
      node(level)
      blk[[top + 1L]] <- list(ind = ind, kind = kind, level = level,
        keys = if (kind == "map") new_keys() else NULL)
    } else {
      if (!is.null(pending)) {
        node(pending$level) # the empty value is a null node
        pending <- NULL
      }
      if (!top) {
        node(1L)
        blk[[1L]] <- list(ind = ind, kind = kind, level = 1L,
          keys = if (kind == "map") new_keys() else NULL)
      } else if (blk[[top]]$ind != ind || blk[[top]]$kind != kind) {
        # indentation YAML does not allow; the parser reports it, the scan only keeps going
        level <- blk[[top]]$level + 1L
        node(level)
        blk[[top + 1L]] <- list(ind = ind, kind = kind, level = level,
          keys = if (kind == "map") new_keys() else NULL)
      }
    }
    if (halted()) break
    fi <- length(blk)
    sm <- simple[[li]]
    if (length(sm) && blk[[fi]]$kind == "map") {
      level <- blk[[fi]]$level + 1L
      check_plain(sm[[3L]], level, key = TRUE, keys = blk[[fi]]$keys)
      if (nzchar(sm[[4L]])) {
        plain <- list(ind = blk[[fi]]$ind, level = level, text = sm[[4L]])
      } else {
        pending <- list(ind = blk[[fi]]$ind, level = level)
      }
      next
    }
    block_content(l, ind + 1L, fi)
  }
  if (!halted()) {
    finish_plain()
    if (!is.null(pending)) node(pending$level)
  }
  list(why = unique(why), safe = !unsafe, limit = limit)
}
