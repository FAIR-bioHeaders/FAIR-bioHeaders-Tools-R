# Round 16 maintenance review — 2026-11-20

Agents prepare and repair PRs; humans merge them. Independent review provenance,
exact tested heads, scanner receipts and detailed finding dispositions belong in
the PR discussion and Round 16 evidence packet. No contract, fixture, provenance
pin, golden expectation, release or supported-format expansion is part of this
maintenance change.

The separate B run supplied the inherited policy and human documentation commits
(user-described Qwen; exact author model/provider not observed). The follow-up
author is Codex (GPT-6; routing variant not exposed). Existing worktrees and old
branches were preserved when the follow-up moved to an isolated branch.

## Scope and results

An actual independent configured `nrp/qwen3` review covered all authored R and C
runtime, maintenance scripts and supplied workflow/documentation source. Its
findings were checked against current source and real fixtures before changes.
The fixes make missing/error FHGM cases fail the aggregate result, stop failed
attempts escaping the per-format limit, classify reader input I/O failures,
reject unused `bh_read(...)` arguments, close failed gzip probes and stage
vendored trees before replacing prior bytes. Diagnostic test output now exposes
individual failures. Regression controls include real missing fixtures and a
failed rename with successful restoration of the old tree.

- Native testthat: 1,217 assertions, zero failures, errors or skips.
- Native released acceptance: all 291 vectors accounted for, 228 documents and
  32 selection probes compared, zero golden differences; 46 capability cells.
- Both existing labelled draft acceptance runners passed. The separate reader
  policy corpus compared 64 cases; its separate 319-case source comparison
  used shared commit `9b5269de0b00186718b07f42b0c48123341ff4de`, manifest
  SHA-256 `7c10fb83bbac5c5739240bff695e5469730ac26a066a51a44d5275598b2df3f6`: 254 carriers compared
  and 65 JSON-LD/microdata cases explicitly unsupported. This supplemental source
  comparison does not repin this consumer or enlarge the frozen 291 baseline.
- Installed API example: plain and gzip checksum verification succeeded; changing
  one sequence byte produced a checksum mismatch and an invalid result. The
  existing R diagnostic labels that mismatch R4; Java/Julia use R3. That existing
  diagnostic difference is recorded without rewriting the frozen default golden.
- Clang static analyzer completed all four authored C translation units with no
  diagnostics. Gitleaks history flagged 295 public synthetic-accession/SHA-256
  literals; every occurrence was checked against its actual historical blob.

R dependency-advisory database coverage was not established by this run. Package
versions and native runtime are recorded in the evidence packet; source review,
C analysis and workflow/history scans do not substitute for that missing coverage.
The first inherited silent test run reported one failure; a later diagnostic
rerun passed, and the final changed suite above passed. Failed setup attempts for
the supplementary policy corpus were retained and corrected, not counted as passes.
