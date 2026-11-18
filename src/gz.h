#ifndef BH_GZ_H
#define BH_GZ_H

#include <Rinternals.h>

SEXP bh_gz_open(SEXP path);
SEXP bh_gz_read(SEXP ptr, SEXP n);
SEXP bh_gz_close(SEXP ptr);

#endif
