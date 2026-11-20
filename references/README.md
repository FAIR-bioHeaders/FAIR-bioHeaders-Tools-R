# Declared reference audit

The adapter reads the current native provenance/registry files at execution time;
`authority-revisions.json` records dereferenced published tag commits separately
from native historical annotated-tag object IDs. Neither source files nor pins
are rewritten. The shared checker is reused at the immutable source/digest in
`checker.json`; bootstrap verifies Git HEAD, immutable blob, digest and symlink
boundaries, and runs those bytes from an isolated private snapshot.

Run `python3 scripts/audit_declared_references.py --checker-root CHECKER`.
`--checkout OWNER/REPO=PATH` supplies offline Git authorities. Online findings
are advisory and include negative probe controls. Missing metadata is not FRESH;
bootstrap/network errors produce QUERY_FAILED, and workflow artifacts are retained.
Strict engine controls use independent temporary Git authorities, never current
moving drafts. The fixed-authority controls run in a separate required job;
only real-reference findings are non-gating advisory results. Draft results are not acceptance, curator review or publication.

The generated inventory explicitly lists coverage gaps. Source/suite pins remain
separate. Full external suite payload completeness is not asserted from a manifest
pin. Actual native draft semantics and final accepted 93/92 suites remain separate
from these historical reference comparisons; no automatic refresh is performed.

## Recorded findings on November 19

The pinned FHT and FHGM suite README copies are adapted local explanatory
material: their recorded local digests differ from the owning README bytes at
those suite commits. The shared audit therefore reports DRIFT for those two
reference groups. This is a declared relationship limitation, not evidence that
payload expectations moved. Existing native `tools/check_vendoring.R` checks
local recorded bytes, while this adapter independently checks source identity.
Neither a local self-consistency pass nor this note changes DRIFT to FRESH.
No byte-identical copy, automatic repin or source-authorized transformation is
invented; a future deliberate provenance change can classify the adapted
README boundaries separately while preserving historical receipts.

Review hardening verifies any recorded native annotated-tag object separately
from its dereferenced commit, including a same-commit retag negative control.
An existing native commit is never replaced by companion metadata. Native
manifest and base-schema declarations are inventoried independently; missing
or conflicting measurements cannot become FRESH.
