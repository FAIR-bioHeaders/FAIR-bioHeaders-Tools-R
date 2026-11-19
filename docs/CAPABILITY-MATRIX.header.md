# Capability matrix: type × operation × serialization × contract version

Status date: **2026-11-18** (re-rendered with the round-13 coordinated draft re-pin: FHT
contract `4156353a` and 82-vector suite, FHGM contract `b7075e58` and 62-vector suite).
This file is the published capability statement of the
`FAIRbioHeadersTools` R package. It is generated from `bh_capability()` by
`tools/render_capability_matrix.R`; the code and this table cannot drift apart
silently, because CI re-renders and compares.

The claim being bounded: **five types registered is not five types supported.**
FHR, FHP and FHGFF3 are released contracts read natively. FHT and FHGM are drafts
under rule V7 of `docs/SCHEMA-VERSIONS.md` (FAIR-bioHeaders-Specification): they
have no `schemaVersion`, no entry in the version registry, no w3id URL, and no
released form here. They are reachable only through the explicit, digest-pinned,
warning-emitting opt-in lane. FHGM is additionally **not a header type at all**:
its records are model records transported inside an FHGFF3 header under
`x-fhgm-models`, carrying no `schema` field of their own. FHGM's two `draft-lane`
cells cover the transport rule (K1, including its carrier-identity clause: the
header must cite a registered FHGFF3 release) and the per-record contract (K2); the
checker's cross-record rules K3-K6 stay `not-supported-yet` with their own rows,
and 43 of the 62 vectors in FHGM's own suite are reported `not-run` rather than
passed.

Draft-scope limitation, stated rather than inherited (round-13, 2026-11-18): the
pinned FHGM record-contract bytes incorporate a widened `layers.model` semantics -
a model `pass` now additionally implies trimmed, invisible-character-free text,
RFC 3986 schemes with a real host, non-blank deposits, NFC-unique identifiers and a
root-level gene target. Upstream itself records that semantics in
`development/conformance/LAYER-SEMANTICS-PROPOSAL.md` as **proposed, not adopted**
(FHGM-Specification#22, #27 and #28 remain open decisions), and the file is vendored
in `tests/draft/fhgm/` only because the suite mirrors the whole upstream non-script
conformance subtree - its presence is not adoption here. K4 abstention is unresolved
upstream; K4 stays `not-supported-yet` in this package **by design**, and all 11 K4
vectors are reported not-run. On the FHT side, 4 of the 82 pinned suite vectors are
marked `promotion: candidate-unreviewed` and are presented as unreviewed candidates,
never as reviewed expectations.

Cell vocabulary:

| mark | meaning |
| --- | --- |
| `native` | implemented in this package, covered by tests here and by the shared-vector run |
| `draft-lane` | implemented against pinned unreleased bytes, reachable only with the rule V7 lane open, warned on every read, never a released-support claim |
| `not-supported-yet` | a gap; the `blocker` column gives the reason and the `tracker` column the issue that owns it. Never blank, never implied by a neighbouring cell |
| `not-applicable` | the combination does not exist in the specification (why is in `blocker`) |

The rows follow. `contract versions` lists what this package bundles and selects
between; released versions come from the v0.6.0 registry (FHR 2.1, FHP 1.2,
FHGFF3 1.2) with historical copies (FHR 1, 2.0; FHP 1.0, 1.1; FHGFF3 1.0, 1.1)
held for rules V2/V3/V6.
