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
### FHGM (draft)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_model_records | nested in fhgff3 via x-fhgm-models | historical draft pin (rule V7) | **draft-lane** | bh_fhgm_models() returns the transported records and bh_draft_pins() names the bytes they were read against; this build retains the historical extension draft; native FHGM 0.1 is published in specification v0.8.0. FHGM records carry no schema field, so the file is routed by its own FHGFF3 citation under V1-V3 and the lane selects only the contract applied to the records. Reads through the shared reader stay uninterpreted extension data (R15); this operation is the opt-in lane, warning on every call. | FHGM-Specification#8,FHGM-Specification#9,FAIR-bioHeaders-Specification#204 |
| validate_model_records | nested in fhgff3 via x-fhgm-models | historical draft pin (rule V7) | **draft-lane** | bh_validate_fhgm() evaluates each record against the pinned draft contract (K2) plus the K1 transport rule (one or more records; no extension at all in an FHGFF3 1.0 header; and a carrier citation a registered FHGFF3 release answers to - raw main and unrecognised citation-version pairs are refused, while v0.5.0 with 1.1 and v0.6.0 with 1.1 or 1.2 are the recognised pairs, maintainer dual-base decision 2026-11-15), and reports the model verdict apart from the base FHGFF3 verdict. Of the 92 pinned development vectors, 37 are compared within K1/K2; 55 require unimplemented K3-K6 or B1 and are reported not-run. Of the 68 invalid vectors, 65 pass both base schema and checksum (66 pass base and 67 checksum individually); those layers alone do not earn a full model verdict. | FHGM-Specification#9 |
| check_model_id_uniqueness | nested in fhgff3 via x-fhgm-models | historical draft pin (rule V7) | **not-supported-yet** | K3 (modelId unique within one snapshot) is a cross-record check the draft checker performs and this package does not; the 8 vectors that turn on it are reported not-run by bh_draft_fhgm_vectors() | FHGM-Specification#9 |
| resolve_feature_target | nested in fhgff3 via x-fhgm-models | historical draft pin (rule V7) | **not-supported-yet** | K4 needs the GFF3 feature layer - featureId as written matching the decoded ID of exactly one local gene row - which belongs to gff3-validator, not to this package; all 18 K4-dependent vectors are reported not-run because this build has no complete trustworthy feature inventory. No K4 or full-model pass is inferred from passing the record schema. | FHGM-Specification#9 |
| check_reference_agreement | nested in fhgff3 via x-fhgm-models | historical draft pin (rule V7) | **not-supported-yet** | K5 compares each record's reference with the enclosing file's genome link and rejects a contradiction; that cross-record comparison is part of the draft checker and is not ported here - only the record's own shape is checked (K2); the 8 vectors that turn on it are reported not-run | FHGM-Specification#9 |
| resolve_revision_pointer | nested in fhgff3 via x-fhgm-models | historical draft pin (rule V7) | **not-supported-yet** | K6 predecessor-pointer resolution against explicitly supplied prior snapshots is not implemented; a resolved pointer would in any case only identify a predecessor, not accept a revision, which is a curator decision. The 21 vectors that turn on it are reported not-run | FHGM-Specification#9,FAIR-bioHeaders-Specification#204 |
| verify_checksum | none | historical draft pin (rule V7) | **not-applicable** | FHGM is not a file type: its records are covered by the checksum of the FHGFF3 file that transports them | NA |
| read_header | fasta,gfa,fhgff3,jsonld,microdata | historical draft pin (rule V7) | **not-applicable** | this historical FHGM extension lane has no separate serialization; native FHGM is outside this build | NA |

### FHT (draft)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_header | fasta (draft) | historical draft pin (rule V7) | **draft-lane** | this build retains the historical FHT draft; family FHT 1.0 is published in specification v0.7.0; readable only with the V7 lane open, against bytes pinned by commit and SHA-256, warning on every read | FHT-Specification#8,FHT-Specification#9,FHT-Specification#10 |
| validate_contract | fasta (draft) | historical draft pin (rule V7) | **draft-lane** | as above; a draft result is not a released-contract result and takes no release form | FHT-Specification#9 |
| verify_checksum | fasta (draft) | historical draft pin (rule V7) | **draft-lane** | the checksum rule is the shared one and runs natively; what is unresolved is selfChecksum/parentLink, which belong to this historical draft pin; this build does not adopt the published FHT contract | FHT-Specification#10 |
| select_schema_V1_V6 | fasta (draft) | historical draft pin (rule V7) | **not-applicable** | V1-V6 cover released types only; V7 is the lane, and a release-shaped FHT URL stays V5 with the lane open or closed | NA |
| verify_parent_links | fasta (draft) | historical draft pin (rule V7) | **draft-lane** | the C3 semantics the FHT development suite states are what bh_verify_links() implements; the evidence for it is the draft suite, not the released vectors | FHT-Specification#8 |
| combine_header,strip_header,convert_serialization | fasta (draft) | historical draft pin (rule V7) | **not-supported-yet** | no write path at all, released or draft | FAIR-bioHeaders-Tools-R#3 |

### FHGFF3 (released)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_header | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **native** | NA | NA |
| verify_checksum | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **native** | NA | NA |
| validate_contract | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **native** | NA | NA |
| select_schema_V1_V6 | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **native** | NA | NA |
| extract_header_yaml | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **native** | bh_extract_header(path) | NA |
| extract_header_json | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **native** | bh_extract_header(path, as = "json") | NA |
| read_header | jsonld,microdata | FHGFF3 1.0, 1.1, 1.2 | **not-supported-yet** | as for FHR: the JSON-LD and microdata readers are unbuilt | FAIR-bioHeaders-Tools-R#3 |
| verify_parent_links | fhgff3 against caller-supplied parent files | FHGFF3 1.0, 1.1, 1.2 | **native** | as for FHR; the annotates and genomeReference forms are both read out of derivedFrom | NA |
| combine_header,strip_header,convert_serialization | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **not-supported-yet** | no write path | FAIR-bioHeaders-Tools-R#3 |
| validate_gff3_features | fhgff3 | FHGFF3 1.0, 1.1, 1.2 | **not-applicable** | feature and biology checking belongs to gff3-validator, not to this package; a valid header says nothing about the features around it | NA |

### FHP (released)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_header | fhp-fasta | FHP 1.0, 1.1, 1.2 | **native** | NA | NA |
| verify_checksum | fhp-fasta | FHP 1.0, 1.1, 1.2 | **native** | NA | NA |
| validate_contract | fhp-fasta | FHP 1.0, 1.1, 1.2 | **native** | NA | NA |
| select_schema_V1_V6 | fhp-fasta | FHP 1.0, 1.1, 1.2 | **native** | NA | NA |
| extract_header_yaml | fhp-fasta | FHP 1.0, 1.1, 1.2 | **native** | bh_extract_header(path) | NA |
| extract_header_json | fhp-fasta | FHP 1.0, 1.1, 1.2 | **native** | bh_extract_header(path, as = "json") | NA |
| read_header | jsonld,microdata | FHP 1.0, 1.1, 1.2 | **not-supported-yet** | as for FHR: the JSON-LD and microdata readers are unbuilt | FAIR-bioHeaders-Tools-R#3 |
| verify_parent_links | fhp-fasta against caller-supplied parent files | FHP 1.0, 1.1, 1.2 | **native** | as for FHR: bh_verify_links(), no automatic file resolution | NA |
| combine_header,strip_header,convert_serialization | fhp-fasta | FHP 1.0, 1.1, 1.2 | **not-supported-yet** | no write path | FAIR-bioHeaders-Tools-R#3 |

### FHR (released)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_header | fasta,gfa | FHR 1, 2.0, 2.1 | **native** | NA | NA |
| verify_checksum | fasta,gfa | FHR 1, 2.0, 2.1 | **native** | NA | NA |
| validate_contract | fasta,gfa | FHR 1, 2.0, 2.1 | **native** | NA | NA |
| select_schema_V1_V6 | fasta,gfa | FHR 1, 2.0, 2.1 | **native** | NA | NA |
| extract_header_yaml | fasta,gfa | FHR 1, 2.0, 2.1 | **native** | bh_extract_header(path) | NA |
| extract_header_json | fasta,gfa | FHR 1, 2.0, 2.1 | **native** | bh_extract_header(path, as = "json") | NA |
| read_header | jsonld | FHR 1, 2.0, 2.1 | **not-supported-yet** | no JSON-LD reader: frame expansion, context handling and rules J1-J9 are unbuilt; 37 shared jsonld vectors stay not-run | FAIR-bioHeaders-Tools-R#3 |
| read_header | microdata | FHR 1, 2.0, 2.1 | **not-supported-yet** | no HTML/microdata reader: implied end tags, itemref/itemid scoping and rules M1-M5 are unbuilt; 26 shared microdata vectors stay not-run | FAIR-bioHeaders-Tools-R#3 |
| read_header | yaml | FHR 1, 2.0, 2.1 | **not-supported-yet** | standalone metadata files are not read: no checksum applies, so this is metadata validation only and it is not implemented yet | FAIR-bioHeaders-Tools-R#3 |
| combine_header | fasta,gfa | FHR 1, 2.0, 2.1 | **not-supported-yet** | no writer: emitting a header means computing a new checksum and choosing canonical YAML quoting, which needs its own tests and its own shared vectors | FAIR-bioHeaders-Tools-R#3 |
| strip_header | fasta,gfa | FHR 1, 2.0, 2.1 | **not-supported-yet** | no writer: strip preserves every other byte, which is a write path, not a read path | FAIR-bioHeaders-Tools-R#3 |
| convert_serialization | fasta,gfa to jsonld,microdata,yaml | FHR 1, 2.0, 2.1 | **not-supported-yet** | no writer, and the target readers are unbuilt too | FAIR-bioHeaders-Tools-R#3 |
| verify_parent_links | fasta,gfa against caller-supplied parent files | FHR 1, 2.0, 2.1 | **native** | no automatic resolution: bh_verify_links() recomputes each cited checksum over the parent path the caller supplies, and an entry with no path is reported unchecked rather than passed | NA |
