# Capability matrix: type × operation × serialization × contract version

Status date: **2026-11-16** (re-rendered with the FHT/FHGM draft-suite re-pin). This file
is the published capability statement of the
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
cells cover the transport rule (K1) and the per-record contract (K2); the
checker's cross-record rules K3-K6 stay `not-supported-yet` with their own rows,
and 34 of the 43 vectors in FHGM's own suite are reported `not-run` rather than
passed.

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
### FHGM (draft)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_model_records | nested in fhgff3 via x-fhgm-models | no released contract (rule V7) | **draft-lane** | bh_fhgm_models() returns the transported records and bh_draft_pins() names the bytes they were read against; no released contract: scheduled as specification v0.8.0. FHGM records carry no schema field, so the file is routed by its own FHGFF3 citation under V1-V3 and the lane selects only the contract applied to the records. Reads through the shared reader stay uninterpreted extension data (R15); this operation is the opt-in lane, warning on every call. | FHGM-Specification#8,FHGM-Specification#9,FAIR-bioHeaders-Specification#204 |
| validate_model_records | nested in fhgff3 via x-fhgm-models | no released contract (rule V7) | **draft-lane** | bh_validate_fhgm() evaluates each record against the pinned draft contract (K2) plus the K1 transport rule (one or more records, and no extension at all in an FHGFF3 1.0 header), and reports the model verdict apart from the base FHGFF3 verdict. That is the earned scope: of the 43 published vectors, 9 turn on K1/K2 alone and are compared; the other 34 turn on K3-K6 or B1 and are reported not-run. earn it. The suite's own manifest records 27 of its 29 invalid vectors passing both the released base schema and the exact-byte checksum (28 pass each one singly), so only those cross-record rules separate them; passing them on the schema layer alone would inflate the claim rather than earn it. | FHGM-Specification#9 |
| check_model_id_uniqueness | nested in fhgff3 via x-fhgm-models | no released contract (rule V7) | **not-supported-yet** | K3 (modelId unique within one snapshot) is a cross-record check the draft checker performs and this package does not; the 5 vectors that turn on it are reported not-run by bh_draft_fhgm_vectors() | FHGM-Specification#9 |
| resolve_feature_target | nested in fhgff3 via x-fhgm-models | no released contract (rule V7) | **not-supported-yet** | K4 needs the GFF3 feature layer - featureId resolving, percent-decoded, to exactly one local gene row - which belongs to gff3-validator, not to this package; the 8 vectors that turn on it are reported not-run | FHGM-Specification#9 |
| check_reference_agreement | nested in fhgff3 via x-fhgm-models | no released contract (rule V7) | **not-supported-yet** | K5 compares each record's reference with the enclosing file's genome link and rejects a contradiction; that cross-record comparison is part of the draft checker and is not ported here - only the record's own shape is checked (K2); the 7 vectors that turn on it are reported not-run | FHGM-Specification#9 |
| resolve_revision_pointer | nested in fhgff3 via x-fhgm-models | no released contract (rule V7) | **not-supported-yet** | K6 predecessor-pointer resolution against explicitly supplied prior snapshots is not implemented; a resolved pointer would in any case only identify a predecessor, not accept a revision, which is a curator decision. The 14 vectors that turn on it are reported not-run | FHGM-Specification#9,FAIR-bioHeaders-Specification#204 |
| verify_checksum | none | no released contract (rule V7) | **not-applicable** | FHGM is not a file type: its records are covered by the checksum of the FHGFF3 file that transports them | NA |
| read_header | fasta,gfa,fhgff3,jsonld,microdata | no released contract (rule V7) | **not-applicable** | FHGM has no serialization of its own | NA |

### FHT (draft)

| operation | serialization | contract versions | support | blocker | tracker |
| --- | --- | --- | --- | --- | --- |
| read_header | fasta (draft) | no released contract (rule V7) | **draft-lane** | no released contract: scheduled as specification v0.7.0; readable only with the V7 lane open, against bytes pinned by commit and SHA-256, warning on every read | FHT-Specification#8,FHT-Specification#9,FHT-Specification#10 |
| validate_contract | fasta (draft) | no released contract (rule V7) | **draft-lane** | as above; a draft result is not a released-contract result and takes no release form | FHT-Specification#9 |
| verify_checksum | fasta (draft) | no released contract (rule V7) | **draft-lane** | the checksum rule is the shared one and runs natively; what is unresolved is selfChecksum/parentLink, which finalize at FHT release | FHT-Specification#10 |
| select_schema_V1_V6 | fasta (draft) | no released contract (rule V7) | **not-applicable** | V1-V6 cover released types only; V7 is the lane, and a release-shaped FHT URL stays V5 with the lane open or closed | NA |
| verify_parent_links | fasta (draft) | no released contract (rule V7) | **draft-lane** | the C3 semantics the FHT development suite states are what bh_verify_links() implements; the evidence for it is the draft suite, not the released vectors | FHT-Specification#8 |
| combine_header,strip_header,convert_serialization | fasta (draft) | no released contract (rule V7) | **not-supported-yet** | no write path at all, released or draft | FAIR-bioHeaders-Tools-R#3 |

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
