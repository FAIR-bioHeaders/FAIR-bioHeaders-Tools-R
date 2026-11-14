/*
 * Line-start scanner used while hashing, for rule R10 (see scan.c).
 */

#ifndef FAIRBH_SCAN_H
#define FAIRBH_SCAN_H

#include <stddef.h>

#define BH_SCAN_MAX_PREFIX 8

typedef struct {
  int enabled;
  unsigned char prefix[BH_SCAN_MAX_PREFIX];
  int plen;
  size_t min_offset; /* count lines that start at or after this 1-based offset */
  long late;         /* header lines found at or after min_offset */

  /* running state */
  int at_start;      /* the next byte begins a line */
  int pending_cr;    /* the last byte was CR, so the terminator is undecided */
  size_t pos;        /* bytes fed so far */
  size_t line_start; /* 1-based offset of the line being matched */
  int match;         /* -1 stopped, 0 not started, 1..plen bytes matched */
} bh_scan;

void bh_scan_off(bh_scan *s);
void bh_scan_on(bh_scan *s, const unsigned char *prefix, int plen, size_t min_offset);
void bh_scan_feed(bh_scan *s, const unsigned char *data, size_t len);

#endif /* FAIRBH_SCAN_H */
