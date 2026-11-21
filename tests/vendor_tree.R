# Stage and verify every related tree before replacing any target. Keep backups
# until the whole group has installed, so a later failure cannot mix revisions.
replace_vendor_trees <- function(sources, targets, rename = file.rename) {
  stopifnot(length(sources) == length(targets), length(sources) > 0L)
  stages <- backups <- rep(NA_character_, length(sources))
  preserved <- installed <- rep(FALSE, length(sources))
  complete <- FALSE
  on.exit({
    if (!complete) {
      for (i in rev(seq_along(targets))) {
        if (installed[[i]]) unlink(targets[[i]], recursive = TRUE)
        if (preserved[[i]] && !isTRUE(file.rename(backups[[i]], targets[[i]])))
          warning("previous vendor tree retained at ", backups[[i]])
      }
    }
    unlink(stages[!is.na(stages)], recursive = TRUE)
  }, add = TRUE)
  inventory <- function(root) {
    files <- sort(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE))
    files <- files[!file.info(file.path(root, files))$isdir]
    stats::setNames(vapply(files, function(f) digest::digest(file.path(root, f),
      algo = "sha256", file = TRUE), ""), files)
  }
  ready <- character(length(sources))
  for (i in seq_along(sources)) {
    source <- sources[[i]]
    target <- targets[[i]]
    if (!dir.exists(source)) stop("missing vendor source tree: ", source)
    if (file.exists(target) && !dir.exists(target)) stop("vendor target is not a directory")
    parent <- dirname(target)
    dir.create(parent, recursive = TRUE, showWarnings = FALSE)
    stages[[i]] <- tempfile(".vendor-stage-", tmpdir = parent)
    dir.create(stages[[i]])
    if (!isTRUE(file.copy(source, stages[[i]], recursive = TRUE))) stop("vendor staging copy failed")
    ready[[i]] <- file.path(stages[[i]], basename(source))
    if (!identical(inventory(source), inventory(ready[[i]]))) stop("vendor staging bytes differ")
    backups[[i]] <- tempfile(".vendor-backup-", tmpdir = parent)
  }
  for (i in seq_along(targets)) {
    if (dir.exists(targets[[i]])) {
      if (!isTRUE(rename(targets[[i]], backups[[i]]))) stop("cannot preserve previous vendor tree; earlier trees restored")
      preserved[[i]] <- TRUE
    }
    if (!isTRUE(rename(ready[[i]], targets[[i]]))) stop("vendor replacement failed; previous trees restored")
    installed[[i]] <- TRUE
  }
  complete <- TRUE
  unlink(backups[preserved], recursive = TRUE)
  invisible(targets)
}

replace_vendor_tree <- function(source, target, rename = file.rename) {
  replace_vendor_trees(source, target, rename = rename)
  invisible(target)
}
