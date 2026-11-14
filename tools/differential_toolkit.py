#!/usr/bin/env python3
"""Supplemental differential: the released Python toolkit against the shared vectors.

This is NOT acceptance for anything. The native R job is acceptance; it does not import,
call or depend on this file, and no R test here needs a Python on the path. What this
script answers is a different question: does the reference implementation still agree with
the manifest the way it did when the vectors were published - and if the R library and this
script ever disagree, which one moved?

Writes a TSV of per-vector verdicts (toolkit exit status and the manifest's own expectation)
so a comparison is a diff of two files rather than a claim in a log.

    python3 tools/differential_toolkit.py [--suite tests/conformance] [--out FILE]

Exit status: 0 when the toolkit agreed with the manifest on every sequence-format vector it
ran, 1 otherwise. A missing `fair-bioheaders` installation is reported and exits 2, because
a differential that did not run must not read as a pass.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", default="tests/conformance")
    ap.add_argument("--out", default="toolkit-verdicts.tsv")
    ap.add_argument("--bin", default="bioheaders", help="bioheaders executable")
    args = ap.parse_args()

    exe = shutil.which(args.bin)
    if not exe:
        print(f"SKIPPED: no {args.bin} executable; install fair-bioheaders to run this "
              "differential. Nothing here gates the native acceptance job.", file=sys.stderr)
        return 2

    ver = subprocess.run([exe, "--version"], capture_output=True, text=True)
    print("toolkit:", (ver.stdout or ver.stderr).strip())

    manifest = json.load(open(os.path.join(args.suite, "manifest.json")))
    rows = []
    for v in manifest["vectors"]:
        if v["format"] not in ("fasta", "gfa", "fhp-fasta", "fhgff3"):
            continue
        path = os.path.join(args.suite, v["file"])
        r = subprocess.run([exe, "verify", path], capture_output=True, text=True)
        rows.append(
            {
                "id": v["id"],
                "format": v["format"],
                "expected": v["expected"],
                "toolkit_exit": r.returncode,
                "toolkit_says": "valid" if r.returncode == 0 else "invalid",
                "agrees": (r.returncode == 0) == (v["expected"] == "valid"),
                "output": (r.stdout + r.stderr).strip().replace("\n", " | ")[:300],
            }
        )

    cols = ["id", "format", "expected", "toolkit_exit", "toolkit_says", "agrees", "output"]
    with open(args.out, "w", encoding="utf-8", newline="") as fh:
        fh.write("\t".join(cols) + "\n")
        for row in rows:
            fh.write("\t".join(str(row[c]).replace("\t", " ") for c in cols) + "\n")

    bad = [r for r in rows if not r["agrees"]]
    print(f"compared {len(rows)} sequence vectors; toolkit disagreed with the manifest "
          f"on {len(bad)}")
    for r in bad[:20]:
        print("  ", r["id"], "expected", r["expected"], "toolkit", r["toolkit_says"],
              "|", r["output"][:120])
    print(f"wrote {args.out}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
