# Capability matrix: type × operation × serialization × contract version

Status date: **2026-11-20**, after the user-requested development-pin refresh:
FHT contract `eb6c36d3` / 93-vector suite `e6ba1c73`; FHGM record contract
`06176262` remains unchanged / 92-vector suite `e8e26d7c`.
This file is generated from `bh_capability()` by `tools/render_capability_matrix.R`;
CI re-renders it and refuses drift between the code and this published table.

**Five types registered is not five types supported.** FHR, FHP and FHGFF3 use
released contracts bundled from specification v0.6.0. This consumer's FHT and
FHGM forms remain an explicit, digest-pinned, warned development lane; the family
has published FHT 1.0 and native FHGM 0.1, but this refresh does not adopt those
released selection forms. The FHT snapshot carries schemaVersion 1.0. FHGM here
is the historical extension model carried inside FHGFF3 under `x-fhgm-models`,
not the published native model representation or a header type.

The FHT lane now enforces owning C1 completeness-count sums with exact integer
arithmetic up to `2^53 - 1` per count; larger values raise `bh_limit` rather than
crediting rounded equality. This consumer limit is not a schema maximum. Schema validation still decides count types and requiredness. Its
93-vector development suite has no `candidate-unreviewed` entries at this pin.
FHGM compares base and checksum on all 92 vectors and the implemented K1/K2
model scope on 37 (6 expected passes and 31 expected rejections). The other 55
are explicitly not-run at the model layer with named gaps: K3 occurs in 8, K4
in 18, K5 in 8, K6 in 21 and B1 in 3; categories overlap. Passing base/checksum
or a record schema never substitutes for those missing predicates or a full
model verdict. The new owning manifest distinguishes historical `layers.model`
process outcomes from earned full-model evidence. This partial consumer reports
its actual scope rather than inheriting a complete model pass from either.

Cell vocabulary:

| mark | meaning |
| --- | --- |
| `native` | implemented in this package, covered by tests here and by the shared-vector run |
| `draft-lane` | implemented against pinned development bytes, reachable only with the rule V7 lane open, warned on every read, never a released-support claim |
| `not-supported-yet` | a gap; the `blocker` column gives the reason and the `tracker` column the issue that owns it. Never blank, never implied by a neighbouring cell |
| `not-applicable` | the combination does not exist in the specification (why is in `blocker`) |

The rows follow. `contract versions` lists what this package bundles and selects
between; released versions come from the v0.6.0 registry (FHR 2.1, FHP 1.2,
FHGFF3 1.2) with historical copies (FHR 1, 2.0; FHP 1.0, 1.1; FHGFF3 1.0, 1.1)
held for rules V2/V3/V6.

Compiled C dependencies and platform CI coverage (`DESCRIPTION` `SystemRequirements`):
`src/` compiles the vendored FIPS 180-4 SHA-512/256 core (`src/sha512.c`, `src/scan.c`)
and the strict gzip reader (`src/gz.c`), linking `zlib` (`PKG_LIBS = -lz` in
`src/Makevars` and `src/Makevars.win`). `src/gz.c` links `zlib` directly rather than
using R's base `gzfile()` connection so that rule-R1 gzip framing verifies every
member's RFC 1952 header, CRC-32 and length trailer, permits multi-member/BGZF streams
and inter-member zero padding, and rejects truncated streams or trailing non-gzip bytes
as classed `bh_input` errors (`gzfile()` silently drops trailing bytes after the last
member). `src/Makevars.win` is provided for standard R `-lz` linking on Windows, but
Windows is **not** in the CI matrix (Ubuntu and macOS are tested in CI; Windows
compilation is not verified).
