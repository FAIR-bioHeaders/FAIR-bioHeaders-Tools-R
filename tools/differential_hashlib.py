#!/usr/bin/env python3
"""Supplemental differential evidence, NOT an acceptance gate.

Write, for every valid sequence-format vector of the vendored shared suite, the
SHA-512/256 of its full DECOMPRESSED bytes (transport is not semantics, so gzip
members are decompressed; unlike rule R3 this hashes every byte including the
checksum line) plus the three FIPS 180-4 / NIST CVL sample messages, using only
CPython's hashlib. The R side (tools/differential_hashlib.R) recomputes the same
inputs with the vendored core and compares. Agreement is cross-implementation
evidence for the digest decision recorded in docs/DIGEST.md; the acceptance
ledger is native and runs in the primary job with no Python installed.
"""
import base64
import gzip
import hashlib
import json
import os
import sys

out = {}

samples = {
    "abc": b"abc",
    "112": (b"abcdefghbcdefghicdefghijdefghijkefghijklmghijklmnhijklmno"
            b"ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"),
    "empty": b"",
}
for label, msg in samples.items():
    out[label] = base64.b64encode(
        hashlib.new("sha512_256", msg).digest()
    ).decode()

suite = sys.argv[1] if len(sys.argv) > 1 else "tests/conformance"
manifest = json.load(open(os.path.join(suite, "manifest.json")))
count = 0
for v in manifest["vectors"]:
    if v.get("expected") != "valid" or not v.get("checksum"):
        continue
    if v["format"] not in ("fasta", "gfa", "fhp-fasta", "fhgff3"):
        continue
    path = os.path.join(suite, v["file"])
    data = open(path, "rb").read()
    if path.endswith(".gz"):
        data = gzip.decompress(data)
    out[v["id"]] = base64.b64encode(hashlib.new("sha512_256", data).digest()).decode()
    count += 1

json.dump(out, open("/tmp/hashlib_digests.json", "w"))
print(f"hashlib differential: wrote {count} vector digests + 3 sample messages "
      "to /tmp/hashlib_digests.json")
