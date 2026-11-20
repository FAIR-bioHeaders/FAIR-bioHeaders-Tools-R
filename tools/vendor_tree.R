# Stage on the destination filesystem; preserve the old tree until copying succeeds.
replace_vendor_tree <- function(source, target, rename = file.rename) {
  if (!dir.exists(source)) stop("missing vendor source tree: ", source)
  parent <- dirname(target)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  stage <- tempfile(".vendor-stage-", tmpdir = parent)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  if (!isTRUE(file.copy(source, stage, recursive = TRUE))) stop("vendor staging copy failed")
  ready <- file.path(stage, basename(source))
  inventory <- function(root) {
    files <- sort(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE))
    files <- files[!file.info(file.path(root, files))$isdir]
    stats::setNames(vapply(files, function(f) digest::digest(file.path(root, f),
      algo = "sha256", file = TRUE), ""), files)
  }
  if (!identical(inventory(source), inventory(ready))) stop("vendor staging bytes differ")
  backup <- tempfile(".vendor-backup-", tmpdir = parent)
  had_old <- dir.exists(target)
  if (file.exists(target) && !had_old) stop("vendor target is not a directory")
  if (had_old && !isTRUE(rename(target, backup))) stop("cannot preserve previous vendor tree")
  if (!isTRUE(rename(ready, target))) {
    if (had_old && !isTRUE(file.rename(backup, target))) {
      stop("vendor replacement failed; previous tree retained at ", backup)
    }
    stop("vendor replacement failed; previous tree restored")
  }
  if (had_old) unlink(backup, recursive = TRUE)
  invisible(target)
}
