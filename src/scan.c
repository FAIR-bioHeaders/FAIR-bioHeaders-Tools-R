/*
 * Line-start scanner used while hashing, for rule R10.
 *
 * docs/FORMAT.md R10: header lines must form the leading block, so a `;~` or `#~`
 * line that begins after the block - including one from a concatenated file - makes
 * the file invalid. Checking that needs every line start in the file, and a reference
 * genome is too large to hold in R, so the check runs in C alongside the hash.
 *
 * The line definition is rule R1: a line ends at LF, at CRLF, or at a CR that is not
 * followed by LF, and the terminator belongs to the line it ends.
 *
 * Positions are file coordinates: bytes counted by bh_scan_feed(), whether or not
 * they were also hashed. The checksum line is excluded from the hash but not from the
 * scan, so a caller can hand it the byte offset it found while reading the header
 * block without converting anything.
 */

#include <string.h>

#include "scan.h"

void bh_scan_off(bh_scan *s) { s->enabled = 0; }

void bh_scan_on(bh_scan *s, const unsigned char *prefix, int plen, size_t min_offset) {
  if (plen <= 0 || plen > BH_SCAN_MAX_PREFIX) {
    s->enabled = 0;
    return;
  }
  (void)memset(s, 0, sizeof(*s));
  memcpy(s->prefix, prefix, (size_t)plen);
  s->plen = plen;
  s->min_offset = min_offset;
  s->at_start = 1;
  s->match = 0;
  s->line_start = 1;
  s->enabled = 1;
}

void bh_scan_feed(bh_scan *s, const unsigned char *data, size_t len) {
  size_t i;
  if (!s->enabled) return;

  for (i = 0; i < len; i++) {
    unsigned char c = data[i];
    int start_line = s->at_start;

    s->pos += 1;

    if (c == '\n') {
      /* LF ends the line, alone or as the second byte of CRLF */
      s->at_start = 1;
      s->pending_cr = 0;
      s->line_start = s->pos + 1;
      s->match = 0;
      continue;
    }
    if (c == '\r') {
      /* undecided: a following LF makes CRLF, anything else ends the line here */
      s->pending_cr = 1;
      s->match = 0;
      continue;
    }
    if (s->pending_cr) {
      /* the CR ended the previous line, so this byte begins a new one */
      s->pending_cr = 0;
      s->at_start = 1;
      s->line_start = s->pos;
      start_line = 1;
    } else {
      s->pending_cr = 0;
    }

    if (start_line) {
      s->at_start = 0;
      if (s->line_start < s->min_offset) {
        s->match = -1; /* before the threshold, so never counted */
      } else {
        s->match = (c == s->prefix[0]) ? 1 : -1;
        if (s->match == 1 && s->plen == 1) {
          s->late += 1;
          s->match = -1;
        }
      }
      continue;
    }

    if (s->match > 0 && s->match < s->plen) {
      if (c != s->prefix[s->match]) {
        s->match = -1;
      } else {
        s->match += 1;
        if (s->match == s->plen) {
          s->late += 1;
          s->match = -1; /* counted; the rest of the line cannot add another */
        }
      }
    }
  }
}
