# STATUS — measured state of the R library

Date: **2026-11-14**, with the 2026-11-15 sections below added for #10 and #12, a
2026-11-16 section for the draft-suite re-pin, a 2026-11-18 section for the
round-13 coordinated draft re-pin, and a 2026-11-19 section for #21 and #23. Everything in
the table was measured on the commit this document accompanied, on macOS 14 arm64 with
R 4.6.1, `jsonvalidate` 1.5.0 (V8 8.2.1), `digest` 0.6.39, `yaml` 2.3.12,
`jsonlite` 2.0.0, `roxygen2` 8.1.0, `testthat` 3.3.2. CI re-measures the same spine on
ubuntu-latest and macos-latest.

## 2026-11-19 — provenance freshness parsing (#23) and shipped-guidance guards (#21)

Measured on branch `round14/b2-r-provenance-guidance` from `origin/main` at `41f51c6c`,
macOS arm64, R 4.6.1. No vendored contract, suite manifest or vector byte under
`inst/schemas/`, `inst/drafts/`, `tests/conformance/` or `tests/draft/` moved.

1. **`draft-pin-freshness` provenance parsing and unusable-input controls (#23).**
   Replaced the inline `grep`/`sed -n '2p'` shell step in `.github/workflows/build.yml`
   with `tools/draft_pin_freshness.R`, which parses `inst/VENDORED.json` (and the
   digest-pinned `tests/draft/fhgm/provenance.json` for the FHGM transport overlay pin)
   via `jsonlite::fromJSON` by exact object path, verifies local vendored files against
   their recorded digests first, runs a non-redirecting 404 control probe per owning
   repository, and prints one labelled row (`TARGET | PINNED | SHIPPED | LIVE | VERDICT`)
   across all five pinned draft targets (`FHT-contract`, `FHT-suite-manifest`,
   `FHGM-record-contract`, `FHGM-transport-overlay`, `FHGM-suite-manifest`). Empty,
   missing or non-64-hex digests, local file mismatches, failed 404 control probes,
   redirects, or unreadable live reads return `UNUSABLE` (exit 2) and never fall through
   into the `MOVED` (exit 1) mismatch branch. `Rscript tools/draft_pin_freshness.R --self-test`
   runs in `build.yml` (both in the primary `build` job and in `draft-pin-freshness`) and
   is also exercised in `tests/testthat/test-docs-claims.R` when the checkout tree is
   present.
2. **Four shipped-guidance defects and compiled-dependency/platform statements (#21).**
   - `docs/NATIVE-ACCEPTANCE.md` now cites the actual SHA-256 of
     `tests/testthat/reference/default-behavior-v0.6.0.json`
     (`02cdf7af3681c96e63c76a2af1bc34459b63a7572f1dc881e0f1c518c9403c41`), and
     `test-docs-claims.R` asserts that the digest quoted in `docs/NATIVE-ACCEPTANCE.md`
     equals the live SHA-256 of the golden file.
   - `README.md` and `docs/STATUS.md` ("Not verified" item 7) now state the current
     FHGM draft-suite figures (**43 of 62** vectors `not-run`, **19** compared at the
     model layer), matching `inst/VENDORED.json`, `man/bh_draft_fhgm_vectors.Rd` and
     `docs/CAPABILITY-MATRIX.md`; `test-docs-claims.R` compares the counts stated in
     `README.md`, `docs/NATIVE-ACCEPTANCE.md`, `docs/CAPABILITY-MATRIX.md`,
     `man/bh_draft_vectors.Rd` and `man/bh_draft_fhgm_vectors.Rd` against the pinned
     records and suite runner counts.
   - `.bh_family_allowed` (`R/read.R`) is derived with `setNames(..., names(.bh_formats))`
     so its keys are pinned to the reader's format vocabulary, and `.bh_family_issue()`
     raises a classed `bh_input` error on any format outside `names(.bh_formats)` rather
     than producing an empty allow-list (`"expected  metadata"`). Covered in
     `test-reader-checks.R`.
   - The `draft-vectors` job in `.github/workflows/build.yml` now uploads
     `fht-draft-vectors.properties` as artifact `fht-draft-vectors-${{ matrix.os }}`
     with `if-no-files-found: error`, matching `fhgm-draft-vectors-${{ matrix.os }}`,
     and `.github/workflows/native-acceptance.yaml` names its matrix legs
     `R CMD check (${{ matrix.os }}, R ${{ matrix.r }})` so the `release` and `oldrel-3`
     Ubuntu legs are distinct.
   - `README.md`, `docs/DIGEST.md`, `docs/STATUS.md` and `docs/CAPABILITY-MATRIX.header.md`
     (plus regenerated `docs/CAPABILITY-MATRIX.md`) document `zlib` (`-lz` in
     `src/Makevars` / `src/Makevars.win`, `DESCRIPTION` `SystemRequirements`) for
     `src/gz.c`'s strict rule-R1 gzip framing and explicitly state that `src/Makevars.win`
     is provided for standard R `-lz` linking on Windows while Windows is not in the CI
     matrix (Ubuntu and macOS are tested in CI).

## 2026-11-18 — round-13 coordinated re-pin: both draft contracts moved, and both suites with them

Measured on this branch's head (fresh clone of `main` at `2b2f5003`), macOS arm64,
R 4.6.1, from sibling checkouts of `FHT-Specification`, `FHGM-Specification` and
`FAIR-bioHeaders-Specification` fetched to `origin/main` first. This is the R half of
a four-library coordinated re-pin; contract **bytes**, not just suites, moved
upstream for the first time.

**What was pinned, re-measured twice.** Every value below was measured from bytes
this pass downloaded or extracted (`shasum -a 256`), then cross-checked against the
content-addressed git blob (`git hash-object` == the contents API's blob SHA at
`ref=main`). A media-type artefact of `Accept: application/vnd.github.raw+json`
(re-encoding `\uXXXX` escapes inside JSON strings) briefly made two API copies
disagree with the raw bytes; the blob SHAs, not that transport, settled it.

| artifact | bytes | sha256 (16) | last-touch commit | repo head | vectors |
| --- | --- | --- | --- | --- | --- |
| FHT contract `fht.json` | 34,396 | `4156353aa6d077fe` | `86438f21` | `0311ddac` | — |
| FHT suite manifest | 76,939 | `e5a4a5d027259e29` | `86438f21` | `0311ddac` | 82 |
| FHGM record contract | 11,522 | `b7075e5872e0a5ff` | `06176262` | `b1a82f82` | — |
| FHGM transport overlay (not vendored here) | 3,191 | `533b3120f4a86590` | `019bc29e` | `b1a82f82` | — |
| FHGM suite manifest | 69,526 | `e41f05fd8bb8b8ec` | `06176262` | `b1a82f82` | 62 |

All five matched the round-13 snapshot; no divergence to report. FHT 82 = 30 valid /
52 invalid, rule census C1 31 / C2 4 / C3 10, still **4** vectors marked
`promotion: candidate-unreviewed`. FHGM 62 = 17 valid / 45 invalid, K1 15 / K2 19 /
K3 7 / K4 11 (3 valid, 8 invalid) / K5 7 / K6 17 / B1 3.

**Re-vendored with the repo's own tool** (`tools/vendor_upstream.R`, extended in
this PR to carry the superseded pin into each record's `previous` field and to
state the limitation paragraph below in the FHGM note). FHT suite 77 → 87 files
(+10 vectors, 0 removed; 75 of the 77 old files byte-identical to live - only
`manifest.json` and `README.md` moved, verified by blob comparison, not assumed).
FHGM suite 28 → 48 files (+19 vectors + `LAYER-SEMANTICS-PROPOSAL.md`, 0 removed;
only `manifest.json`, `README.md`, `provenance.json` and `base_matrix.json` moved
among the old 28). Examples: 30 → 30 files, all 30 byte-identical (verified). 10
upstream `*.py` scripts are left behind (`not_vendored`; the set grew by
`examples/revision/check_revision.py`, and the drop behaviour is unchanged). The
released block is untouched: `inst/schemas/`, `tests/conformance/` and the
293-file / 291-vector / combined `5a05499f...` record are byte-identical, and
`inst/VENDORED.json`'s `conformance` block did not move in the diff.

**`LAYER-SEMANTICS-PROPOSAL.md` is vendored, deliberately, and disclosed.** The
tool mirrors the whole upstream non-script conformance subtree; this package
already vendors upstream prose (`README.md`, `PROMOTION-2026-11-15.md`), and
excluding one file would put an editorial exception into the byte-mirror rule. The
file states its own status on its first line - *proposed, not adopted*, refs
FHGM#22 - and the vendored note, the capability matrix and this section all say
that its presence is mirror fidelity, not endorsement.

**combined_sha256 reproduced independently.** Recomputed from each record's
`per_file` map (locale-sorted `"<path> <sha256>"` join, LF): FHT `6ebb39e143ee0059`,
FHGM `caa494ac9e984c57`, shared `5a05499f2f9d8fe3` - all three reproduce their
recorded values exactly; on-disk verification: 87/87, 48/48 + 30/30 and 293/293
files, **0 mismatches, 0 missing, 0 extras**.

**Two behavioural consequences of the new bytes, both in the draft lane only.**
First, K1's carrier-identity clause - "refuses a citation no registered release
answers to (raw main, superseded releases)" - had never been exercised: the new
`carrier-cites-raw-main` vector exposed that `bh_validate_fhgm()` did not evaluate
it, and it is now implemented and tested (including the two dual-base accept forms
the re-pin also newly exercises, `v0.6.0-citation-stating-1.1` and
`fhr-specification-alias-v0.6.0`). The accepted citation shapes come from ONE
shared grammar (`.bh_release_url_re`, R/selection.R) that selection and K1 both
consume - the w3id release URL with or without a trailing slash, and the raw tag
URL under either repository name - which is exactly what the checker's own
`development/model/base-schemas.json` registers; a test pins the eight registered
spellings and the cross-layer agreement in both directions. Second,
`fht-fasta-gzip-truncated` is scored on the R1 condition established EXTERNALLY:
`.bh_gz_stream_truncated()` re-reads the cited bytes and independently detects the
gzip magic plus an unfinished member - "there are no decompressed bytes for R1 to
hash and the file is rejected before any checksum comparison" - the same reading
the toolkit's FHT lane applies. The manifest's `selfChecksum: unreachable` label
may narrow the exception but never grounds it: a vector may not certify its own
unreachability (maintainer ruling, 2026-11-18, round-13 P-6 review recorded on this
PR's thread; no org issue number records it, and the earlier citations
FAIR-bioHeaders-Tools#146 / spec#139 are withdrawn as verified wrong - #146 is a Zenodo
DOI PR, spec#139 the voucher-specimens issue; verified adjacent implementations: Java
commit `2c35d938` ("nothing passes for the wrong reason") and FHT-Specification#37,
which finalizes the `selfChecksum` field's semantics). Five
standing controls, red-first against the earlier revisions of this PR: the pinned
vector passes; the declaration deleted from a scratch manifest -> `error`; the
R2 missing-checksum fixture replaced with truncated-gzip bytes -> `error` (the
first revision falsely passed it); a complete member followed by trailing non-gzip
bytes -> `error` (a refusal to frame is not a truncation); and the re-review's
counterexample - the live R1 vector's bytes replaced with a COMPLETE, readable gzip
whose payload no longer matches the recorded checksum - -> `error` on the
normal-return path too, never the generic `pass` at `09241ade` (the R4 rejection is
not R1's truncation evidence; a vector whose bytes parsed cannot evidence
unreachability). The released reader
taxonomy and the released 291 ledger are untouched.

**Review follow-ups on this branch (2026-11-18, same day).** The independent review
of the first head found three blockers, each fixed with red-first proofs and its own
commit: (1) the K1 clause above initially refused the w3id trailing-slash spelling
that `R/selection.R:28` has always accepted - one package contradicting itself - now
resolved by the shared grammar with a battery over both layers; (2) the gzip
scoring initially keyed on the vector's own declaration, reproducing the
self-certifying-`unreachable` failure mode the maintainer had already ruled out
elsewhere in this round - now grounded externally as above; (3) the vendor
generator initially rewrote `previous` on every run, so an unchanged rerun erased
the last real pin transition - `previous` now rotates only when the resolved
digests move, proven by `tools/selftest_vendor_previous.R` (bare-origin fixture
repos, six generator runs: unchanged rerun byte-identical, one-lane move rotates
only that lane, a second move rotates to the immediately prior pin, and a SUITE-
manifest move takes `rotate_suite`'s change branch - the branch runs 1-4 never
exercised - with the other suite's history byte-stable), wired as a
build step because `tools/` is excluded from the tarball and a skip would violate
the zero-skip rule. The independent re-review of that head (`gpt-6.1-terra`) found
the gzip exception still open on the NORMAL-RETURN path - a complete, readable gzip
with a stale checksum line passed the live R1 vector through the generic verdict
comparison (reproduced red at `09241ade`: `status: pass`, R4 diagnostic) - and the
same conjunction now binds both paths: an R1-labelled `unreachable` vector whose
bytes PARSED is reported error, never passed on a borrowed rejection, while an
observed `valid` still flows to the normal comparison and fails as a substitution
should. That re-review also established the `FAIR-bioHeaders-Tools#146` /
`spec#139` citations were WRONG - #146 is a Zenodo CITATION.cff PR, spec#139 the
voucher-specimens issue - and they are retracted here, in the code comments, and in
the amended commit history, leaving the honest form (maintainer ruling, 2026-11-18,
round-13 P-6 review recorded on this PR's thread; no org issue number records it)
plus the verified adjacent implementations (Java commit `2c35d938`, "nothing passes
for the wrong reason"; FHT-Specification#37, which finalizes the `selfChecksum`
semantics). The citation battery now asserts selection outcomes for the negative
forms as well, owning the two domain differences instead of claiming universal
layer identity: v0.4.0 selects as the real released 1.0 contract under V3 while K1
refuses the transport pairing, and raw main is selection's V1 question, not the
carrier's. The `draft-pin-freshness` advisory job is NOT cited as corroboration
anywhere in this record - it is broken per `Tools-R#23` (independently reproduced:
empty digest extractions, positional `sed -n '2p'` reading FHT's superseded digest
against FHGM's live manifest), and its fix belongs to a separate branch;
`native-acceptance.yaml` naming its legs by OS only, collapsing the release and
oldrel-3 legs into one displayed name, is recorded as a CI-reporting follow-up, not
bundled here.
An unchanged-input rerun of the fixed generator against the
real owning repositories left `inst/VENDORED.json` byte-identical.

**Measured acceptance counts.** The model layer's compared set was not predicted
but measured through R's own scope rule over both new manifests via
`tools/acceptance_fhgm.R`'s receipt: 62 evaluated, base 62/62, checksum 62/62,
**model layer compared 19** (6 expected passes, 13 expected rejections), **43
not-run** naming K3 (7) / K4 (11) / K5 (7) / K6 (17) / B1 (3) - labels counted per
naming, some vectors name two. `n_eval <- 62L`, `n_model <- 19L` in the tool and
in the workflow's literal ledger. 42 of the 45 invalid vectors pass both the base
schema and the checksum layer (43 and 44 singly), which is what the capability
matrix now states. The suite-label census moved 29/14 → 17 `rules` arrays / 45
singular `rule`, zero unlabelled.

**Pins proven consumed.** Extracting the superseded suites (FHT `be9bcc82`, FHGM
`d443073a`) and pointing each runner at them refuses with the digest message
(`REFUSED`, before any vector runs); re-running against the vendored bytes gives
82/82 and 62/62-ok again, and `tools/check_vendoring.R` stays clean afterwards.

**Spine.** `tools/run_tests.R`: `tests=1131 failed=0 errors=0 skipped=0`
(1046 before the PR, 1111 at the first review-fix head, +20 from the re-review's
normal-return counterexample and the negative selection assertions; **1199 on 2026-11-19
after round 14 #21/#23** — the freshness self-test wired as a CI step, the prose-claim
tests, and the format-vocabulary assertions);
`tools/check_duplicate_defs.R` OK; native-path grep clean; `tools/acceptance_native.R`
291 / 228 / 63 with golden `goldenDifferences=0`; both draft receipts green with
the literals above; matrix re-renders byte-identically (46 cells); differential
`90 inputs, 0 mismatches`; `R CMD check --as-cran --no-manual` (idle machine):
`Status: 2 NOTEs`, exit 0, packaged tests `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1057 ]`.
**Re-measured 2026-11-19 at round 14 (#21/#23), same idle-machine discipline**:
`tests=1199 failed=0 errors=0 skipped=0`; `R CMD check --as-cran --no-manual`
exit 0 with `Status: 3 NOTEs` — "New submission" (unavoidable), the five upstream
portable-path names (structural, disclosed below and unchanged), and the
worktree-local `.git` artifact of running `R CMD build` inside a `git worktree`
(in the normal main checkout and in CI the directory form is handled the way it
always was). The earlier `no visible global function definition for 'head'` NOTE
that the first round-14 run produced is fixed in the same pass: `R/conformance.R`
now qualifies `utils::head()`. This block's golden reference, stated once so the
history above reads correctly: the default-behavior golden has been
`02cdf7af3681c96e63c76a2af1bc34459b63a7572f1dc881e0f1c518c9403c41` since `9fc09203`;
the dated "still `055da14f...`" sentences above are accurate to their own commits, and
`docs/NATIVE-ACCEPTANCE.md` — the verification document #21 item 1 was about — now
cites `02cdf7af...` with a test holding the quoted digest to the real file.
The first NOTE is the unavoidable "New submission" one. The second is new with
this pin and structural, not accidental: five of the FHGM suite's new vector file
names exceed R's 100-character portable-path limit once they sit under
`FAIRbioHeadersTools/tests/...`. The bytes and their names are vendored upstream
material - the manifest cites each path and `per_file` digests it - so renaming
here would edit vendored bytes, which this repository does not do. The `build.yml`
check step gates WARNINGs and the exit status and prints NOTEs, so this stays a
reported NOTE, said here rather than smoothed over. The testthat
floor moved 700 → 1000 with the measured count, per the rule that the floor is
the real count rounded down.

**Known-stale things deliberately NOT fixed here** (FAIR-bioHeaders-Tools-R#21,
separate reviews): the stale golden digest `055da14f...` quoted in
docs/NATIVE-ACCEPTANCE.md, the README's pre-#14 "24 of its 31", the unpinned
format vocabulary behind `.bh_family_allowed`, and the missing FHT receipt
artifact. One adjacent staleness this PR does *necessarily* clear: regenerating
the man pages corrected `man/bh_draft_fhgm_vectors.Rd`, which already said "31
vectors" while the source said 43 on `main` - the generated docs were stale
**before** this change; the regeneration is required by the source prose, and the
pre-existing discrepancy is disclosed so nobody reads the fix as an introduced
error.

## 2026-11-16 — issue #12 warning-fallback regression

The [maintainer ruling](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Tools-R/issues/12#issuecomment-6907515161)
retains `paste(c(message, ...), collapse = "")` and declines `Collate:`. The re-pin
PR #14 is merged. `tests/testthat/test-warning-fallback.R` now deliberately makes
`sprintf("%s %d", "a")` fail, calls the installed namespace's `bh_warn()` directly,
and checks the exact joined message `%s %da`, all four warning classes, and the
invisible `NULL` return. In an isolated R process, replacing the fallback with the
deleted bare-message alternative makes exactly the message assertion fail; the
other four assertions pass. No source file or pin is changed by that control.

Measured on macOS 27.2.1 arm64, R 4.6.1, testthat 3.3.2, using a source-built
package installed into an isolated library:

- `tools/run_tests.R`: **790 assertions, 0 failures/errors/skips** (785 on the
  merged re-pin baseline plus these five assertions).
- `tools/acceptance_native.R`: **291 accounted for, 228 pass, 63 declared not-run
  with reasons**; golden comparison: 291 vectors, 228 documents, 32 selection
  cases, **0 differences**.
- `tools/acceptance_draft.R`: **72/72 FHT**; `tools/acceptance_fhgm.R`: **43/43 base
  and checksum agreement, 9 model comparisons, 34 named not-run**, unchanged.
- Duplicate-definition, native-path and offline vendoring guards pass; parsed
  expressions in both edited `R/` files are identical to the merged baseline.
  The 46-cell capability matrix is byte-identical after regeneration.
- Full `R CMD check --as-cran --no-manual` completes with **0 errors/warnings**,
  including all 790 packaged test assertions. Its two NOTEs are new submission
  and the linked-worktree `.git` file. The final tarball is built from a clean
  source export without `.git`; `R CMD check --as-cran --no-manual --no-tests`
  on that export reports **1 NOTE (new submission), 0 errors/warnings**. The full
  packaged tests were already run above; the packaging-only check does not count
  skipped tests as passing.

Contracts, suite pins/fixtures, golden bytes, `DESCRIPTION`, `NAMESPACE`, the
existing CI warning/count gates and the duplicate-definition guard are unchanged.
The older dated measurements below remain historical evidence, not current counts.

## 2026-11-16 — deliberate re-pin of the two draft suites; the two contracts stay put

Measured on this branch's head, macOS 27.2.1 arm64, R 4.6.1, with the sibling checkouts
`FHT-Specification` and `FHGM` fetched to `origin/main` first. This is a provenance
re-pin, not a feature: the vendored draft suites had moved upstream while this package's
records still described the 2026-11-14 revisions.

**Spine, re-measured on this head.** `tools/run_tests.R`: `tests=785 failed=0 errors=0
skipped=0` (770 before this PR; the 15 additions are the new parentLink comparison: one
per-vector link-count assertion over 10 vectors plus its 5 census and equality assertions).
Ledger `291 / 228 pass / 0 fail / 63 declared-not-run-with-reason`; default-behavior golden
still `055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525` with
`goldenDifferences=0`; `tools/check_duplicate_defs.R` exits 0 at 144 top-level assignments /
144 distinct names; `tools/render_capability_matrix.R` re-renders byte-identically
(`5b43306968cb8181e948d30f7a73460aad70f23ed1a7b4ec159a9a28f92b96ab`). `R CMD check --as-cran
--no-manual`, same invocation (R 4.6.1, macOS 27.2.1 arm64, from a fresh clone in both cases):
before = `Status: 1 NOTE`, exit 0, 66 check lines, `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 770 ]`
inside the check; after = `Status: 1 NOTE`, exit 0, 66 check lines,
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 785 ]`, i.e. no new WARNING or NOTE - the NOTE is the unavoidable "New submission" one, and the
log-parse guard in `build.yml` still fires only on a WARNING (0 matches on the clean logs; it
matches as designed when a WARNING line and a `Status: 1 WARNING, 2 NOTEs` line are appended
to a copy).

**What moved, and what demonstrably did not.** Every value below was re-measured from
content-addressed git blobs (`git show <rev>:<path>`, `git cat-file -s`), not from
`raw.githubusercontent.com`, and sizes are bytes actually written out, not `HEAD`
content-length.

| record | old | new | how measured |
| --- | --- | --- | --- |
| FHT contract `fht.json` | `59ad9641adcb0e55...` / 29,430 B @ `226f923c` | **unchanged** (live `main` = `be9bcc82` serves the same digest) | `git show origin/main:fht.json \| shasum -a 256` |
| FHT suite manifest | `9b07179497bdc724...` / 66 vectors | `9fd8c0b2a4638d5d...` / 65,615 B / 72 vectors | same, at `be9bcc82` |
| FHT suite tree | 69 files, combined `71e3e3ad...` | 77 files, combined `86231b50...` | `tools/check_vendoring.R` after re-extraction |
| FHGM record contract | `bf1553cac04dc88d...` / 9,564 B @ `ac3d37b3` | **unchanged** (blob `1fb066b8da5bf5bb...` at `ac3d37b3` and at head `57118c52`) | `git show origin/main:development/model/fhgm-model.schema.json` |
| FHGM transport overlay | `dd9f69274f26860b...` / 1,363 B | `d1619cced91b4ef5...` / 2,613 B (dual-base framing, FHGM #17) | `git show origin/main:development/model/fhgm-draft.schema.json` |
| FHGM suite manifest | `31f14f022ff08581...` / 35,269 B / 31 vectors | `0d2790151c4a2955...` / 51,114 B / 43 vectors | `git show origin/main:development/conformance/manifest.json` |
| FHGM suite / example trees | 17 + 23 files | 28 + 30 files | re-extraction, upstream `.py` files left behind |

**Contract pin ≠ suite pin, and the two now provably differ.** FHT: contract `226f923c`,
suite `be9bcc82`. FHGM: contract `ac3d37b3`, suite `d443073a`. Both jobs assert all four
strings in their receipts, so collapsing them into one value fails CI rather than passing
quietly. `tools/vendor_upstream.R` previously wrote the FHT *suite* pin as the branch head
at retrieval, which conflates "the tree I happened to hold" with "the revision of the
suite"; it now derives it the way it already derived FHGM's, from the commit that last
touched that suite's manifest.

**Digest first, count second.** FHGM's manifest went 35,269 → 51,114 bytes while its
count went 31 → 43, and the intermediate step (36,001 B with the count still 31) was
invisible to any count-only assertion. Both are pinned here: the manifest SHA-256 is
re-digested by `tools/check_vendoring.R` and by the runner before a single vector is read,
and the count is checked against it afterwards.

**The 12 new FHGM vectors are real-data promotions, and only two of them are in this
package's model scope.** FHGM #18 promoted ten gap-proof *rejection* cases from the
Drosophila chr4 example lane, each with a matching pair of valid anchors, so the manifest
grew 31 → 43: 10 `dmel-*` invalids plus `dmel-snapshot-v1` and `dmel-snapshot-v2-resolved`.
Two of the ten (`dmel-empty-model-array` = K1, `dmel-numeric-model-version` = K2) fall
inside the scope this package evaluates; the other eight name K3/K4/K5/K6 and are not-run.
The re-measured split for the whole suite: 43 evaluated, base 43/43, checksum 43/43,
**9 compared at the model layer** (3 accepts, 6 K1/K2 rejections), **34 not-run** naming
K3 (5) / K4 (8) / K5 (7) / K6 (14) / B1 (2). Every sealed expectation of the old 31 is
byte-identical in the new manifest - no previously published verdict was rewritten by the
promotion - and no new vector became a pass that the checker's own rules do not let it be.

**A guard added while measuring.** The runner treated a vector with no rule label as
in-scope (`setdiff(character(0), …)` is empty, so "comparable"). None of the 43 pinned
vectors is unlabelled — 29 label through `rules`, 14 through the singular `rule` — so this
is a shape guard, not a finding about the current bytes; had the labels been dropped, 14
expected rejections would have entered the compared set silently. Unlabelled now means
`not-run` with the reason stated, and the receipt carries `vectorsNotRunUnlabelled`, which
CI pins at 0.

**The pins are consumed, and a tamper proves it.** With one byte-pinned field changed in
each of four places (both suite manifests, the vendored `tests/draft/fhgm/provenance.json`,
and the *installed* draft contract copy), `tools/check_vendoring.R` reported 4 DRIFT lines and
exited 1; `bh_draft_pins()` reported `digest_ok = FALSE` for FHGM; `bh_validate_fhgm()`
refused with "the bundled draft bytes no longer match their recorded digest"; both suite
runners aborted naming the found and pinned manifest digests; and both acceptance scripts
exited 1 writing **no receipt**. Every mutation was byte-verified before concluding from it
(the needle occurred exactly once, and the file digest moved), and every file was restored
with `cmp` clean against its pre-tamper copy. `tools/check_vendoring.R --fresh --fht … --fhgm
…` then confirmed both contract pins unchanged against the live default branches; those heads
had in fact advanced twice more today, by AGENTS.md-only PRs, leaving both conformance trees
byte-identical (`eda186fd…`, `5eb338ef…`) - a good illustration of why the pin is a digest and
a manifest's last-touch commit rather than a branch head.

**A new comparison, prompted by the re-pin.** The FHT manifest's `parentLink` entries state a
sealed outcome per link (`checked-pass` / `checked-fail` / `unchecked`), but the shared runner
reads only the cited parent *file* and derives its own verdict, so no green run had ever
compared the two. `test-draft-vectors.R` now walks all 12 links over 10 vectors and requires
the derived verdict to equal the sealed one, link by link: 7 pass, 4 fail, 1 unchecked (the
one whose `file` is null stays unchecked rather than becoming a pass). All 12 reproduce
natively at the pinned revision.

**Re-pinning is a deliberate act and is never automated.** Nothing here runs on a schedule:
the advisory `draft-pin-freshness` job only *reports* drift. A re-pin is a commit that
states what moved, keeps the two contract rows on their own commits, and re-runs the whole
spine afterwards.

## 2026-11-15 — six duplicate top-level definitions removed, and a guard added (#12)

Measured in a fresh clone of `main` at `4611c2c`, on macOS 27.2.1 arm64, R 4.6.1.

**The state before the change.** `R/` holds 150 top-level assignments, 128 of them function
definitions, under 144 distinct names; **six names are defined twice**. #12's table gives five
names and 126 definitions; the sixth found here is `%||%`, defined at `R/framing.R:34` and
`R/internals.R:12`. The five names #12 lists reproduce in the same files; their line numbers in
`R/conditions.R` are 9 higher than the issue recorded because #11 inserted a comment block in that
file (verified: `git diff 9827944f..4611c2c -- R/conditions.R` touches only roxygen and comment
lines, no code).

| name | copy 1 | copy 2 | comparison of the two definitions |
| --- | --- | --- | --- |
| `bh_abort` | `R/conditions.R:29` | `R/internals.R:42` | raw source bytes identical |
| `bh_warn` | `R/conditions.R:40` | `R/internals.R:55` | **differs semantically** (`63e96156c4d83e9f` vs `43727c8387068674`) |
| `.bh_capture` | `R/conditions.R:55` | `R/internals.R:73` | differs by one line, no behaviour change (see below) |
| `.bh_read_all` | `R/conditions.R:76` | `R/internals.R:18` | raw source bytes identical |
| `.bh_c` | `R/framing.R:81` | `R/internals.R:14` | raw source bytes identical |
| `%||%` | `R/framing.R:34` | `R/internals.R:12` | raw source bytes identical |

Four pairs are byte-identical as written. Hashes are SHA-256(16) of the definition after
`deparse()` canonicalisation, used to compare the two that differ, so indentation and line wrapping
can neither fake a difference nor hide one.

`.bh_capture` is the case worth recording precisely, because a raw text difference here is not a
behaviour difference: after canonicalisation the two bodies differ by exactly one line — the
`R/conditions.R` copy pre-declares `val <- NULL` immediately before assigning `val` again — and both
copies, called the way the package calls them (expression passed lazily), return `identical()`
results on all four traced inputs: no condition, two `bh_warn` calls, one `bh_abort`, and a warning
followed by an error. The live binding agrees with both. #12 records this so the duplicate audit is
not read as "two behaviourally different captures".

**Which copy ran, established by execution.** The package was built and installed from the
tarball and each name was read out of the loaded namespace with `getFromNamespace()`. For all six
names the installed binding equals the `R/internals.R` copy; the `R/conditions.R` copies of
`bh_warn` and `.bh_capture` are the only two whose canonical text differs from the live binding,
which is the direct evidence that they were unreachable. `R/internals.R`'s `bh_abort` uses the same
`paste(c(message, ...), collapse = "")` fallback as its `bh_warn`, so the retained module is the
internally consistent one, as #12 predicted. A two-file control package (`R/conditions.R` and
`R/internals.R` defining `dupe()` differently) was installed the same way and its namespace returns
`"from-internals.R"` — the shadowing rule is measured, not argued.

Behavioural discriminator for `bh_warn`, with `sprintf()` failing (`bh_warn("draft", "%s %d", "a")`):
the live binding reports `’%s %da’` (the `paste()` fallback), the deleted `R/conditions.R` copy would
have reported `’%s %d’`. Neither is exported (`NAMESPACE` lists neither), and both call sites —
`R/fhgm.R:152`, `R/read.R:99` — pass `bh_warn("draft", "%s", w)`, where `sprintf()` succeeds, so no
reachable path exercised the divergence before or after this change.

**What was done.** The six dead copies were deleted; `R/internals.R` is now the sole owner of all
six helpers. Nothing else in `R/` changed. `R/conditions.R` keeps the `conditions` topic and
recorded the deleted `bh_warn` fallback as an open question rather than silently discarding it.
The later 2026-11-16 ruling retains the joined-parts fallback;
`tests/testthat/test-warning-fallback.R` now directly tests its exact message and warning classes.
`Collate:` was declined; the duplicate-definition guard remains the CI gate.

**Evidence that nothing moved.** `tools/check_duplicate_defs.R` is new; `R/` goes from 150
top-level assignments / 144 distinct names to 144 / 144. A canonical dump of every object in the
loaded namespace (154 objects, 32 exports, functions printed via `deparse()`, native symbols by
name only) is byte-identical before and after — SHA-256
`302b870c81978963564ce66d1fe75e3d3c15e5ce80fe655fa1834e398a5f5379` for both, `cmp` clean. On top of
that: `tests=770 failed=0 errors=0 skipped=0` (unchanged, and no test calls `bh_abort()`/`bh_warn()`
directly); ledger `291 / 228 pass / 0 fail / 63 declared not-run`; golden `goldenDifferences=0` with
`tests/testthat/reference/default-behavior-v0.6.0.json` still SHA-256
`055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525`; FHT draft lane 66/66; FHGM draft
lane 31 evaluated / 7 model-compared / 24 not-run; `docs/CAPABILITY-MATRIX.md` byte-identical after
`tools/render_capability_matrix.R` (`1b4b0bbd4fddd9ea029e2b3975ad9fabb2ade66a5663d1c696c4d652d53b71a9`).
Every receipt file is byte-identical between the two runs (`cmp`). `R CMD check --as-cran
--no-manual` reports `Status: 1 NOTE` with exit 0 both before and after — the same unavoidable
"New submission" NOTE — and the two logs are identical apart from paths and timings (`diff` after
stripping those: empty). No `man/` file changed: no roxygen block was removed, and the
`read.Rd`/`yaml-shape.Rd` trailing-blank-line artifact that `roxygen2::roxygenise()` produces on
this tree appears identically on pristine `main`, so it was reverted again under the same rule as
above.

**The guard, and why it is not a status check.** `R CMD check` cannot catch this: on the two-file
control package it exits 0 and the word "duplicate" appears nowhere in its log, and on `main` at
`4611c2c` it exits 0 while reporting `Status: 1 NOTE` (#11 measured the same with
`Status: 1 WARNING, 1 NOTE`). So `tools/check_duplicate_defs.R` is its own static analysis — it
parses `R/*.R`, takes every top-level name assignment (`<-`, `<<-`, `->`, `->>`, `=`, and `assign()`
with a literal name), and exits 1 on any name bound twice, identical bodies included, exiting 2 when
it cannot see `R/` at all so that an unreadable tree is never a pass. It runs as a failing step in
both workflows (`build.yml`, `native-acceptance.yaml`). Red/green was demonstrated four ways: on the
real pre-fix tree (6 violations), on the fixed tree (green), after re-appending the identical
`.bh_c` to `R/framing.R`, and after re-appending the divergent `bh_warn` copy to `R/conditions.R`
(reported as `copies DIFFER`), plus a same-file duplicate and a directory with no `R/`. Each
mutation was proven non-vacuous with `cmp` against the pre-mutation file, and each revert was
verified byte-identical. Separately, the `R CMD check` steps now keep their log and fail on any
`WARNING` line, which is the detection #12 asked about: it is wired, not just recommended. NOTEs are
printed and not gated, because the "New submission" NOTE and the macOS pandoc NOTE are unavoidable
and would make the leg permanently red.

**A defect in the guard itself, caught by testing its own untested branch.** The first version
parsed `Collate:` looking for double-quoted file names. DESCRIPTION fields quote with single
quotes, so a package that declared `Collate:` fell through to alphabetical order while the
violation line still asserted a load order — with `Collate: 'zzz.R' 'aaa.R'` it named `zzz.R:1` as
live where the installed namespace binds `aaa.R`'s (`a(3)` returns `3`). Both quote forms now
parse, continuation lines included, files the field omits are placed first as `R CMD INSTALL`
does, and a `Collate:` field that yields no names stops the run with exit 2 instead of guessing:
the order is what the message claims, so it is not a thing to fall back on. The operator list also
read `->=` where `->>` was meant; R normalizes right-assignment before the script sees it
(`parse(text = "(f) ->> a")` gives `<<-(a, f)`), so nothing was missed on the forms this package
uses, and `->`, `->>`, `assign()` and non-function duplicates are each now tested to exit 1.

**CI on this branch.** `build` and `Native acceptance` are green at `6bff0b5` (runs 43751103290,
43751103350) and at `601eba6` (43751582981, 43751582983). The guard step runs on all three `Native
acceptance` legs — including `oldrel-3` on **R 4.3.3**, job 132926503619 — and every leg then prints
`R CMD check: no WARNING in check.log (exit status 0)`; the `build` legs print the same for
`build-check.log`. At `2ca8f76` one duplicate was put back deliberately, its bytes proven (`R/framing.R`
sha256 `79c44686f516…` → `2046b18a58b8…`, `cmp` reporting `EOF`), and **both workflows fail**
(43751638775, 43751638779) with `Assert no name is defined twice in R/` as the only failed step in
each job — the `build` jobs also fail `Upload native reports`, because the job aborted before the
receipts it uploads were ever written. The `oldrel-3` leg fails the same way (job 132926683363), so
the gate is proven on R 4.3.3 as well as on 4.6. `6ef9ea3` reverts the probe and both workflows are
green again (43751655760, 43751655787). The `oldrel-3` attribution uses the REST per-job logs
endpoint (`actions/jobs/{id}/logs`), because `Native acceptance` has two jobs named
`R CMD check (ubuntu-latest)` and the name-keyed `gh run view --log --job=` route returns
byte-identical logs for both — the trap #11 recorded.

**What each CI leg reports for `R CMD check`, at `6267975` (runs 43753148520 and 43753148506)**, each
value taken from that job's own REST log rather than from the run-wide log: `Status: 1 NOTE` on
`build (ubuntu-latest)` (R 4.6.2, job 132931336686) and `Status: 2 NOTEs` on `build (macos-latest)`
(R 4.6.2, job 132931336287) — "New submission", plus the known pandoc NOTE under
`checking top-level files` — and `Status: OK` on all three `Native acceptance` legs: R 4.3.3
(`r-version: oldrel-3`, job 132931336408), ubuntu release (job 132931336532) and macOS (job
132931336141), none of which pass `--as-cran`. Every one of those five legs also prints
`R CMD check: no WARNING in …-check.log` and `check_duplicate_defs: OK - every top-level name in R/
is defined once`, so the new gate is green on the NOTEs it deliberately does not treat as failures.
One caution, because it bit the extraction: the string `Status: 1 WARNING` also appears in these job
logs as **echoed step text**, since the workflow comments quote #11's measurements. Only a bare
`Status: …` output line is a result, and the counts above are from those.

*Supersedes* the "**Found while doing this, deliberately not changed**" paragraph in the #10 section
below, which recorded these duplicates as left in place on purpose. That was the right call for a
documentation-only PR; #12 is the code change it deferred, so that paragraph is kept as the record of
what #10 measured and should not be read as the current state.

## Baseline comparison, honestly framed

The stub package on `main` before this work reported `Status: OK / 39 checks /
0 notes` **because it was empty**: no compiled code, no exports beyond a
placeholder, no tests. Those 39 checks are not a quality bar; the numbers below
are the first real ones for this repository.

| measure | stub (main, `4b975bd`) | v0.6.0 core + lane (main, `8957f4f`) | this work (FHGM model lane) |
| --- | --- | --- | --- |
| `R CMD check --as-cran --no-manual` | 39 checks, 0 notes, Status OK | recorded by that revision as "66 checks, 0 errors, 0 warnings, 1 NOTE"; **not reproducible in this session** — the same commit `8957f4f`, checked here with the toolchain above, reports 1 WARNING and 1 NOTE | **0 errors, 1 WARNING, 1 NOTE** (66 check lines, 53 `checking` steps; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 770 ]` inside the check). The NOTE is the unavoidable "New submission"; the WARNING is `Rd files with duplicated alias 'bh_abort'` (`man/conditions.Rd` and `man/internals.Rd`), present at `8957f4f` as well, so nothing here introduces it. Removing the duplicate roxygen block is a separate cleanup. The CI legs report the same pair (`build (ubuntu-latest)`: 1 WARNING, 1 NOTE); the macOS leg adds one NOTE, "Files 'README.md' or 'NEWS.md' cannot be checked without 'pandoc' being installed", which is a runner toolchain artifact of that workflow (it installs no pandoc) and not a package finding. |
| testthat assertions | 0 | **561, 0 failed, 0 errors, 0 skipped** (re-measured locally at `8957f4f`) | **770, 0 failed, 0 errors, 0 skipped** |
| shared v0.6.0 vectors | not run | **291 accounted: 228 pass natively, 63 not-run with reasons, 0 fail** | unchanged: the receipt is byte-identical to the one produced at `8957f4f` |
| default-behavior golden | none | `goldenDifferences=0` | `goldenDifferences=0`; the golden file is still SHA-256 `055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525` |
| FHT development suite (draft lane only) | not run | **66/66 pass** against pinned bytes, in the separate labelled job | unchanged, same job |
| FHGM development suite (draft lane only) | not run | not run (the checker was not on `main`; see below) | **31 evaluated: base 31/31, checksum 31/31; model layer compared on the 7 K1/K2 vectors, all agreeing; 24 `not-run` naming K3-K6/B1** |
| compiled digest self-test | none | runs at every package load; refuses to load on any mismatch | unchanged |

## 2026-11-15 — the `R CMD check --as-cran` WARNING is gone (#10)

Re-measured on this commit, macOS arm64, R 4.6.1, `roxygen2` 8.1.0:

| measure | before (`9827944`) | after (this commit) |
| --- | --- | --- |
| `R CMD check --as-cran --no-manual` | `Status: 1 WARNING, 1 NOTE`, from `checking Rd metadata ... WARNING` / `Rd files with duplicated alias 'bh_abort': 'conditions.Rd' 'internals.Rd'` | `Status: 1 NOTE`, from `checking Rd metadata ... OK` |
| `checking` steps | 53 | 53 |
| testthat inside the check | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 770 ]` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 770 ]` |

The one remaining NOTE is the same unavoidable "New submission" under `checking CRAN
incoming feasibility`. The two `00check.log` files differ in exactly three places — the
`Rd metadata` block, the test timings, and the `Status:` line — verified with `diff` after
writing each log to its own file and stripping only the log-directory and timestamp lines.

**Why CI stayed green with a WARNING on `main`.** `.github/workflows/build.yml` does use
`--as-cran`: its `R CMD check (the spine)` step is
`R CMD check --as-cran --no-manual FAIRbioHeadersTools_*.tar.gz`.
`.github/workflows/native-acceptance.yaml` runs the check with `--no-manual` and *without*
`--as-cran`. Neither step can fail on a warning: `tools:::.check_packages()` in R 4.6.1
calls `do_exit(1L)` only when `Log$errors > 0L`, and the run on the unmodified tree exited
0 while reporting `Status: 1 WARNING, 1 NOTE`. So no flag suppressed the warning — the
spine job has been printing it — the step is just not wired to fail on one. Turning a
WARNING red is a CI change and belongs with #4, so it is not done here.

**The same two workflows, read out of CI's own logs, `main` vs this branch.** Each row is
the `checking Rd metadata` line and the `Status:` line of one job, taken from that job's own
log (`actions/jobs/{id}/logs`; note that `gh run view --log --job=` keys on the job *name*,
and `Native acceptance` has two jobs called `R CMD check (ubuntu-latest)` whose logs came
back byte-identical under that route — `cmp` proved it, so the per-job endpoint is what the
figures below come from).

| leg | flag | R | `main` at `9827944` | this branch at `e858b31` |
| --- | --- | --- | --- | --- |
| `build.yml` / `build (ubuntu-latest)` | `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING, 1 NOTE` | OK, `Status: 1 NOTE` |
| `build.yml` / `build (macos-latest)` | `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING, 2 NOTEs` | OK, `Status: 2 NOTEs` |
| `native-acceptance.yaml` / ubuntu release | no `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING` | OK, `Status: OK` |
| `native-acceptance.yaml` / macOS | no `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING` | OK, `Status: OK` |
| `native-acceptance.yaml` / ubuntu oldrel-3 | no `--as-cran` | **4.3.3** | WARNING, `Status: 1 WARNING` | OK, `Status: OK` |

Both runs on this branch are green end to end: `build` run 43728815985 (8 jobs, all
`success`, including the ledger and golden literal assertions) and `Native acceptance` run
43728815989 (3 jobs, all `success`).

Two corrections come out of this. The NOTE count on every leg is unchanged before and after
(the macOS legs carry the documented pandoc NOTE, the `--as-cran` ubuntu leg carries
"New submission", the legs without `--as-cran` carry neither), and **#10's assumption that
`--as-cran` is what surfaces the WARNING is wrong**: `Rd metadata` printed it on all five
legs above, including the three that never pass `--as-cran`, on R 4.6.2 and R 4.3.3 alike.
The WARNING was always printed, everywhere, and acted on nowhere.

**Which module owns the documented topic.** `R/internals.R` now documents
`bh_abort()`/`bh_warn()` alone (#10's option 1). `R/conditions.R` keeps the `conditions`
topic — the classed error/warning surface — and points at the helpers with `@seealso`; its
duplicate roxygen block is a plain comment. Reasons, in the order that decided it: the copy
that actually runs is `R/internals.R`'s, because there is no `Collate:` field, so
`R/conditions.R` is collated first and `R/internals.R` overwrites the shared bindings
(confirmed by installing this tree and reading `bh_warn`'s body out of the namespace: it
carries the `paste(c(message, ...), collapse = "")` handler from `R/internals.R`, not the
`error = function(e) message` one from `R/conditions.R`); and `man/internals.Rd` documents
the pair together with `@keywords internal`, while `man/conditions.Rd` documented
`bh_abort()` only and never `bh_warn()`. #10's option 2 rests on callers meeting the helper
through conditions; what a caller meets is the condition classes, which is what the
`conditions` page describes, and that page stays where it was.

**Found while doing this, deliberately not changed.** `bh_abort()`, `bh_warn()`,
`.bh_read_all()` and `.bh_capture()` are each *defined* twice on `main`, once per module.
`bh_abort()` and `.bh_read_all()` are byte-identical between the two files (verified with
`cmp`); `bh_warn()` differs in its `sprintf()`-failure fallback. Only the `R/internals.R`
copies are reachable. Removing the shadowed copies is a code change, and no test calls
`bh_abort()` directly or exercises either fallback — its documented behaviour is covered
only indirectly, by the `expect_error(..., class = "bh_*")` assertions in
`test-conformance.R`, `test-draft-lane.R`, `test-engine-pin.R` and `test-fhgm-lane.R` — so
it is left for its own decision. `R/conditions.R` now says this above the copies.

**Unmoved, re-measured on this commit:** ledger `vectorsTotal=291 vectorsRun=228
vectorsPassed=228 vectorsFailed=0 vectorsNotRun=63`; golden `goldenDifferences=0`, with
`tests/testthat/reference/default-behavior-v0.6.0.json` still SHA-256
`055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525`; `tests=770`,
`skipped=0` from `tools/run_tests.R` against the CI floor of 700; FHT draft receipt 66/66
and FHGM draft receipt 31 evaluated / 7 model-compared / 24 not-run, both against their
pinned bytes and digests; `docs/CAPABILITY-MATRIX.md` byte-identical after re-running
`tools/render_capability_matrix.R` (46 cells).

**How `man/` was regenerated, and one thing reverted.** `Rscript -e
'roxygen2::roxygenise()'` (roxygen2 8.1.0, `Roxygen: list(markdown = TRUE)`), not a hand
edit. That run also appended a trailing blank line to `man/read.Rd` and
`man/yaml-shape.Rd`, which is unrelated to #10 and was reverted rather than committed: no
committed `man/*.Rd` ends with two LF bytes (checked across all 44), so this is an artifact
of re-running roxygen here, not a content difference. Every other `man/` file regenerates
byte-identical, so `man/conditions.Rd` is the only documentation page this change alters.

## What is implemented (native, released types)

- Vendored FIPS 180-4 SHA-512/256 (`src/sha512.c`), streaming with rule-R3 range exclusion
  and the rule-R10 line scanner (`src/scan.c`), plus the strict `zlib` gzip reader
  (`src/gz.c`, linked via `PKG_LIBS = -lz` in `src/Makevars` / `src/Makevars.win` and
  declared in `DESCRIPTION` `SystemRequirements`) that verifies RFC 1952 member headers,
  CRC-32 and length trailers, multi-member/BGZF concatenation and zero padding while
  rejecting truncated members or trailing non-gzip garbage that R's base `gzfile()`
  silently ignores; decision and evidence in docs/DIGEST.md.
- Byte-exact framing (rules R1-R7, R10), YAML semantics (R8, R12, R13), warning
  reporting (R11, R14, empty-required), contract validation with `engine = "ajv"`
  asserted and dialect-probed, selection rules V1-V6, parent-link verification
  (`bh_verify_links`), gzip/BGZF transport, the five-type registry
  (`bh_types`/`bh_contracts`/`bh_capability`).
- The 291-vector native runner with the seven guards in
  docs/NATIVE-ACCEPTANCE.md, the default-behavior golden, receipts. The golden is
  byte-identical between the core revision and this one: the lane changed nothing
  by default (`goldenDifferences=0` both sides).

## Draft state (rule V7; never a support claim)

- FHT: opt-in lane, pinned contract `86438f21c3a17a58334c97aed4955be1a2393522`
  (SHA-256 `4156353aa6d077fe...`, 34,396 bytes; re-verified 2026-11-18 by digest and by
  content-addressed blob against the owning repository's live `main` = `0311ddac...`),
  suite `86438f21...` - the commit that last touched `conformance/manifest.json`,
  computed separately from the contract pin and coinciding with it at this pass -
  (manifest `e5a4a5d027259e29...`, 76,939 bytes, 82 vectors, 87 files), 82/82
  pass; warns on every read; release-shaped FHT URLs stay V5. FHT publishes as
  specification v0.7.0 (FHT-Specification #8/#9/#10). #8's boxes 3/4/6/7 are still
  open upstream, so this pin is expected to move again. 4 of the 82 vectors remain
  marked `promotion: candidate-unreviewed` and are presented as unreviewed.
- FHGM: **not a header type**. Its records are transported inside an FHGFF3 header under
  `x-fhgm-models` and carry no `schema` field, so the lane selects only the contract applied
  to the records. Contract bytes registered and digest-pinned (`06176262f9824f26d974a15d8feeebde1fbeb0a8`,
  SHA-256 `b7075e5872e0a5ff...`, 11,522 bytes - re-verified 2026-11-18 against the owning
  repository's live `main`, whose head is `b1a82f82...`);
  the suite bytes are vendored under `tests/draft/fhgm` plus the `tests/draft/examples`
  files its vectors cite (48 + 30 files, manifest `e41f05fd8bb8b8ec...`, 69,526 bytes,
  62 vectors; suite commit `06176262...` - the commit that last touched that manifest,
  derived by the same rule as the contract pin and coinciding with it at this pass).
  10 upstream `*.py` scripts are left behind (`not_vendored`), and the suite's
  `LAYER-SEMANTICS-PROPOSAL.md` is vendored with the subtree as upstream prose whose
  status it states itself: proposed, not adopted.
  `bh_fhgm_models()` / `bh_validate_fhgm()` / `bh_draft_fhgm_vectors()` are the lane: they
  evaluate K1 (transport: one or more records, no extension at all in an FHGFF3 1.0
  header, and - new in the 2026-11-18 pin - a carrier citation a registered FHGFF3 release
  answers to) and K2 (each record against the pinned draft contract) and report the model
  verdict apart from the base FHGFF3 verdict. K3-K6 are **not** ported and stay named gaps with their
  own matrix rows; 43 of the 62 vectors are `not-run` for exactly that reason (7 K3, 11 K4,
  7 K5, 17 K6, 3 B1; a vector can name two rules). A vector with no rule label is `not-run` too, never assumed in-scope.
  The suite's `base_matrix.json` (FHGFF3 1.2 re-observation lane, twin bytes not vendored) is
  not evaluated here. Opt-in only,
  warns on every record read, and `schemaVersion`, registry row and w3id URL are all absent,
  as rule V7 requires. Tracked in #3; FHGM publishes as specification v0.8.0.
- Freshness of all five draft targets (FHT contract, FHT suite manifest, FHGM record
  contract, FHGM transport overlay, FHGM suite manifest) was last verified 2026-11-19
  against the owning repositories' live default branches (`tools/draft_pin_freshness.R`,
  run by the advisory CI job `draft-pin-freshness`, which parses `inst/VENDORED.json`
  with `jsonlite::fromJSON` by exact object path, verifies local vendored copies first,
  runs a 404 control probe, and exits 2 on any unusable input).

## The FHGM re-land (2026-11-14): what this section replaces

`docs/STATUS.md` at `8957f4f` said FHGM's checker was "not ported, not partial, not
claimed", and `bh_capability()` held `read_model_records` / `validate_model_records` at
`not-supported-yet`. Both were accurate for that commit, and both were the residue of a
merge accident rather than a decision to drop the work: on 2026-11-14 two parallel R PR
chains were merged minutes apart (#5 → #7 from `feat/native-sha512-256`, #6 → #8 from
`pr1/native-core`/`pr2/v7-draft-lane`) and `main` resolved to the #6/#7 content, so the
checker that the other chain carried - `R/fhgm.R`, `R/fhgm-run.R`, the vendored FHGM suite
and its tests - landed on `feat/native-sha512-256` (merge `3418cb8`) and never reached
`main`. Nothing on `main` was broken by that: `build` and `Native acceptance` were green at
`8957f4f`, and no document claimed the missing code.

This revision re-lands the checker onto `main` by port, not by re-merge, because the
surrounding modules on `main` are the other chain's: `.bh_resolve_named()`/`.bh_search()`
and the locator tests came over, `tools/run_conformance.R` did not (its role here is
`tools/acceptance_fhgm.R`, in the shape of the existing `tools/acceptance_draft.R`), and the
capability cells were rewritten for main's matrix rather than copied. `src/sha512.c` is the
same blob on both chains (`131f49cd58b9...`) and was not touched.

What is *newly* claimed, and what is not: the two FHGM cells move from `not-supported-yet`
to `draft-lane` for K1/K2 only, four named gap rows (K3-K6) are added, the shared ledger is
untouched at 291/228/63, and the default path is unchanged (golden identical).

**A defect the deliberate-failure probe caught.** With the not-run policy temporarily
removed, `s6k-derived-record-fixture` disagreed with its published expectation in the other
direction: this package's K2 layer *rejected* a record the suite records as `pass`. The cause
is not the contract and not the fixture. R's `yaml` returns an atomic vector for a
one-item sequence, so the fixture's `"deposit":["doi:10.22002/e86gh-a7p16"]` reaches
`.bh_record_json()` as a scalar, and the pinned record contract - which declares
`publication.deposit` an array - rejects it. The released header path already repairs that
shape from the text (`R/yaml-shape.R`), but its scanner is line-oriented and cannot see
inside a flow value; that was harmless while every array-typed property in the released
contracts was a top-level key (measured over `fhr-2.1`, `fhp-1.2`, `fhgff3-1.2`: still true).
The FHGM record contract is the first in the family with an array nested inside an object
(`publication.deposit`, `methods.limitations`), so the lane needed its own text-derived scan
(`.bh_fhgm_flow_scalar_keys()`, `R/fhgm.R`). Nothing is coerced from the contract: a key is
re-wrapped only because this file's bytes wrote brackets around it, and the standing test
asserts both halves - the fixture's array survives, and the same bytes with the brackets
removed are still rejected (2 bytes fewer, proven on the file). The repair lives in the draft
lane only; the released path and the golden do not move.

## Ledger (v0.6.0 baseline; identical figures from the Java library)

    vectorsTotal=291 vectorsRun=228 vectorsPassed=228 vectorsFailed=0
    vectorsNotRun=63 vectorsDeclaredNotRunWithReason=63
    fasta=98/98 passed, 0 not run        gfa=56/56 passed, 0 not run
    fhp-fasta=36/36 passed, 0 not run    fhgff3=38/38 passed, 0 not run
    microdata=0/26 passed, 26 not run    jsonld=0/37 passed, 37 not run

## Not verified (deliberately; each is a claim someone else's measurement must make)

1. **Linux/Windows compilation and check results.** The C core was compiled and
   exercised on macOS/arm64 only locally; ubuntu coverage arrives with the CI
   runs of this PR and is not asserted here until those runs are green and
   recorded below by date.
2. **Large-file behaviour.** The streaming path is proven byte-correct on the
   suite (largest vector is small) and the head-reading path refuses oversized
   header blocks; no gigabyte-scale reference genome was hashed in this session.
3. **`selfChecksum`/`parentLink` draft semantics** beyond what the FHT suite's
   C1/C3 vectors state; they finalize at FHT release (FHT-Specification #10).
4. **Any performance claim.** No benchmarks were run.
5. **Bioconductor/CRAN acceptance.** Out of scope for these PRs by instruction;
   submission is a maintainer action.
6. **Microdata and JSON-LD readers** do not exist here (63 not-run vectors,
   reasons declared per row) — their rules (M1-M5, J1-J9, R9) are not "almost"
   covered by anything in this package.
7. **FHGM cross-record model rules** K3 (modelId uniqueness in a snapshot), K4
   (feature-target resolution against the GFF3 feature layer), K5 (record/file
   reference comparability) and K6 (predecessor-pointer resolution): not ported,
   named as their own matrix rows, and their 43 vectors (out of 62 in the pinned
   suite; 19 are compared at the model layer) are reported `not-run`
   rather than passed. The upstream checker (`validate_fhgm.py`) stays the
   reference for them and is deliberately not vendored here.
8. **FHGM revision/curator semantics.** A resolved pointer would only identify a
   predecessor, never accept a revision; that is a curator decision (shared #204)
   and nothing here claims it.
9. **Windows**: `src/Makevars.win` is provided for standard R `-lz` linking on
   Windows and the package declares no OS restriction, but Windows is not in the
   CI matrix (Ubuntu and macOS are tested in CI) and has not been compiled or tested.

## Provenance notes

- 2026-11-16 re-pin: only the two **suite** blocks of `inst/VENDORED.json` and the vendored
  trees under `tests/draft/` moved, plus `tests/draft/fhgm/provenance.json` (now the owning
  repository's `provenanceVersion` 2 record, byte-identical to its `origin/main` blob
  `9cf5c218e4e3dad0...`). The 9 released-contract rows, the version-registry row, the two
  draft-**contract** rows and the whole shared `conformance` block are unchanged in the JSON
  (asserted field-by-field before writing, and re-audited by `tools/check_vendoring.R`).
  `combined_sha256` values were recomputed with the same recipe the record was written with
  - a locale-sorted `"<path> <sha256>"` join - and the recipe was validated first by
  reproducing the superseded values `71e3e3ad...` and `3ab6118f...` exactly from the old
  trees before using it to write the new ones.
  SHAs for released-contract rows (all rows consistently; for example the
  v0.6.0 tag object `ab7e3ddd53bfccee9a31d59fc10524eadf32c1da` dereferences to
  commit `0ae18b00ee4bd71ab2dc28bae706b0f9d195076b`). Byte identity was verified
  against `git show v0.6.0:<path>`, which dereferences the tag.
- Every vendored byte was re-verified 2026-11-14 three ways: local file digest
  == recorded digest == upstream bytes at the pinned ref (293 shared-suite files,
  69 FHT draft-suite files, 9 contracts, the registry, 2 draft schemas). The FHGM
  set was vendored again for this revision, from a fresh clone of FHGM-Specification
  at `origin/main` = `52b07b7a`: 17 suite files and 23 example files, each written
  with `git show origin/main:<path>` and hashed here, and every digest-bearing
  field of the resulting `draft_fhgm_vectors` block (per-file SHA-256, manifest
  `31f14f02...`, combined `3ab6118f...`, contract `bf1553ca...` of 9,564 bytes at
  commit `ac3d37b3`) independently reproduced the values the lost branch had
  recorded. The 7 upstream generator/checker `.py` files are recorded as
  `not_vendored` and stay upstream. The ported `tools/vendor_upstream.R` step was then
  run end-to-end in a scratch clone against that same fresh FHGM clone: it wrote 17 + 23
  files byte-identical to what is committed (`diff -r`, empty) and a block identical in
  every digest-bearing field. Two residual differences are prose, not digests, and both
  are pre-existing in kind: `repository` is taken from the given checkout's own `origin`
  (the tool writes the HTTPS `FHGM-Specification` URL where the committed rows, including
  `main`'s FHGM contract row, name the SSH redirect `git@github.com:FAIR-bioHeaders/FHGM.git`),
  and the tool's `commit_field` sentence is older than the refined text in the committed
  file, so a full re-vendor would revert it. Neither is settled here; the shared and FHT
  blocks reproduce exactly.
- What the FHGM lane does **not** vendor: the transport overlay contract
  (`development/model/fhgm-draft.schema.json`, the FHGFF3-with-`x-fhgm-models`
  shape) and the reference checker (`development/model/validate_fhgm.py`). This
  package validates records against the pinned record contract and reads the
  transport from the parsed header; the overlay is not asserted here, and K3-K6
  remain upstream's checker.
- The federation's R capability study is archived at docs/CAPABILITY.md
  (single-host measurement; the digest route in this repo supersedes its open
  question as a **decision**, with the alternatives and why they were rejected
  recorded in docs/DIGEST.md).

## November 19, 2026 adopted reader-policy implementation

This source implements D9/D10 from shared #211: schema selection precedes
validation; R4 canonical encoding is checked for root and standard derivedFrom
checksums without inspecting arbitrary extension payloads; YAML directives and
document-start wrappers are refused; gzip trailing garbage is rejected, trailing
NUL padding is accepted, and FHCRC is verified when present. Native supplementary
runner commands and their exact shared-source pin are in the reader-policy CI
workflow and `references/reader-policy.json`. This is runtime implementation,
not a rewrite of frozen released schema patterns.

The historical 291 manifest, fixtures and default golden remain unchanged. A
byte-bound shared retirement crosswalk records the 30 formerly valid synthetic
parent fixtures now rejected under R4. Historical expectations remain readable;
the native historical runner explicitly reports the new effective rejection.
The existing golden is compared through exact predecessor/new-row policy deltas,
not regenerated. Current canonical-parent counterparts exercise the original
predicates independently. Supplementary/current-source results are distinct from
the v0.6.0 ledger, draft FHT/FHGM receipts and any publication/support claim.

`references/README.md` documents the dynamic advisory reference audit; it never
refreshes contract/suite/carrier pins automatically. Existing dated 82/62 draft
receipts are historical, not accepted93/92 or published support.

Review correction: the historical-manifest runner now verifies each original
retired payload digest and evaluates its separately named canonical counterpart
before crediting the original predicate. Its rows retain `id`, `evidence_id`,
`evidence_file` and historical expectations. The receipt splits159 original
payload results from69 byte-bound canonical counterparts (nine other crosswalk
entries are JSON-LD/microdata and remain explicitly not-run); neither the old48
invalid fixtures' R4 rejections nor the old30 positives prove those predicates.
The frozen fixture/golden bytes remain unchanged. The policy/current-carrier
runner requires three-way unsupported-version verdicts and accepts only two
named gzip transport error causes; other errors stop execution.
