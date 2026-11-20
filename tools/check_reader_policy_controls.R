#!/usr/bin/env Rscript
# MPL-2.0. Execute the exact runner transport classifier against independent failures.
suppressPackageStartupMessages(library(FAIRbioHeadersTools))
forms <- parse('tools/acceptance_reader_policy.R')
classifier <- Filter(function(x) is.call(x) && length(x)>=3L &&
  identical(x[[1L]],as.name('<-')) && identical(x[[2L]],as.name('transport_rejection')),as.list(forms))
stopifnot(length(classifier)==1L)
context <- new.env(parent=globalenv());eval(classifier[[1L]],context)
check <- context$transport_rejection
error <- function(class,message) structure(list(message=message,call=NULL),class=c(class,'bh_error','error','condition'))
case <- list(id='fasta-policy-gzip-fhcrc-wrong')
stopifnot(identical(check(error('bh_input','gzip FHCRC mismatch'),case,''),'invalid'))
stopifnot(identical(check(error('bh_input','bytes follow the last gzip member'),list(id='fasta-policy-gzip-trailing-garbage'),''),'invalid'))
rejected <- function(e,c=case) inherits(tryCatch(check(e,c,''),error=function(x)x),'error')
stopifnot(rejected(error('bh_schema','gzip FHCRC mismatch')))
stopifnot(rejected(error('bh_dialect','schema engine failed')))
stopifnot(rejected(error('bh_input','file is missing')))
stopifnot(rejected(error('bh_input','gzip FHCRC mismatch'),list(id='fhp-metadata-selection-v0-3-1')))
stopifnot(rejected(error('bh_input','gzip FHCRC mismatch'),list(id='fasta-policy-plain-control')))
cat('reader policy transport controls: 7 passed; unrelated errors are never negative evidence\n')

# A real substitution that would otherwise borrow an R4 rejection for P1.
check_counterpart_digest <- function(policy_root) {
  source <- dirname(normalizePath(policy_root,mustWork=TRUE))
  crosswalk <- jsonlite::fromJSON(system.file('references','retirement-crosswalk.json',package='FAIRbioHeadersTools'),simplifyVector=FALSE)$cases
  case <- Filter(function(c) identical(c$id,'fhp-fasta-derived-from-bad-relationship'),crosswalk)[[1L]]
  target <- tempfile('reader-policy-counterpart-control-');dir.create(target)
  on.exit(unlink(target,recursive=TRUE),add=TRUE)
  files <- list.files(source,recursive=TRUE,all.files=TRUE,full.names=TRUE,no..=TRUE)
  for (file in files) {
    dest <- file.path(target,substring(file,nchar(source)+2L))
    dir.create(dirname(dest),recursive=TRUE,showWarnings=FALSE)
    stopifnot(file.copy(file,dest,overwrite=TRUE))
  }
  old <- file.path(source,case$file);replacement <- file.path(target,case$replacementFile)
  stopifnot(identical(digest::digest(file=old,algo='sha256'),case$oldSha256))
  stopifnot(identical(digest::digest(file=replacement,algo='sha256'),case$replacementSha256))
  stopifnot(!identical(readBin(old,'raw',file.info(old)$size),readBin(replacement,'raw',file.info(replacement)$size)))
  stopifnot(file.copy(old,replacement,overwrite=TRUE))
  log <- tempfile();on.exit(unlink(log),add=TRUE)
  status <- suppressWarnings(system2(file.path(R.home('bin'),'Rscript'),
    c('tools/acceptance_reader_policy.R',shQuote(file.path(target,'reader-policy'))),stdout=log,stderr=log))
  stopifnot(status!=0L,any(grepl('replacementSha256',readLines(log,warn=FALSE),fixed=TRUE)))
  cat('counterpart control: substituted old invalid payload refused by digest before predicate credit\n')
}
args <- commandArgs(TRUE)
stopifnot(length(args)==1L)
check_counterpart_digest(args[[1L]])
