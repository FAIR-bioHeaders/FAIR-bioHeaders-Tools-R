#!/usr/bin/env python3
# MPL-2.0. Adapter controls use only local declaration snapshots; no real pin changes.
import copy, importlib.util, json, shutil, tempfile
from pathlib import Path
p=Path(__file__).with_name("audit_declared_references.py")
spec=importlib.util.spec_from_file_location("audit",p)
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
base=audit.inventory()
assert base["advisory"] is True and base["references"]
assert all(r["files"] for r in base["references"])
assert {"released-contract","draft-contract","conformance-suite","base-carrier"} <= {r["class"] for r in base["references"]}
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)
    for record in base["declarationRecords"]:
        target=root/record["path"];target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(audit.ROOT/record["path"],target)
    assert audit.inventory(root)==base
    # Mutate actual recorded digest; adapter must report it verbatim, never
    # silently replace metadata with a checksum computed from the local file.
    record=next(x["path"] for x in base["declarationRecords"] if x["path"]!="references/authority-revisions.json")
    data=json.loads((root/record).read_text())
    files=data["files"]
    entry=files[0] if isinstance(files,list) else next(iter(files.values()))
    old=entry["sha256"];entry["sha256"]="0"*64
    (root/record).write_text(json.dumps(data))
    assert old!="0"*64
    changed=audit.inventory(root)
    assert changed!=base
    assert any(f["sha256"]=="0"*64 for r in changed["references"] for f in r["files"])
    assert changed["declarationRecords"]!=base["declarationRecords"]
print("adapter controls: 8 passed; independent shared engine controls are separate")
