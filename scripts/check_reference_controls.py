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

# Independent annotated-tag identities: same commit, different tag object.
import subprocess
with tempfile.TemporaryDirectory() as tmp:
    authority=Path(tmp)/"authority";authority.mkdir()
    def git(*args): return subprocess.check_output(["git","-C",str(authority),*args],stderr=subprocess.PIPE).decode().strip()
    git("init");git("config","user.name","Synthetic reference control");git("config","user.email","control@example.invalid")
    (authority/"x").write_text("control\n");git("add","x");git("commit","-m","synthetic authority")
    commit=git("rev-parse","HEAD");git("tag","-a","v1.0.0","-m","first object")
    original=git("rev-parse","refs/tags/v1.0.0")
    table={"references":[{"id":"tag","repository":audit.AUTHORITY,"revision":"v1.0.0","tagObject":original,"requiresTagObject":True}]}
    mapping=[audit.AUTHORITY+"="+str(authority)]
    assert audit.tag_identity_findings(table,mapping)["tag"]["verdict"]=="FRESH"
    table["references"][0]["tagObject"]="0"*40
    assert audit.tag_identity_findings(table,mapping)["tag"]["verdict"]=="DRIFT"
    table["references"][0]["tagObject"]=""
    assert audit.tag_identity_findings(table,mapping)["tag"]["verdict"]=="ABSENT"
    table["references"][0]["tagObject"]=original
    git("tag","-f","-a","v1.0.0","-m","different object same commit")
    assert git("rev-parse","v1.0.0^{commit}")==commit
    assert git("rev-parse","refs/tags/v1.0.0")!=original
    assert audit.tag_identity_findings(table,mapping)["tag"]["verdict"]=="DRIFT"
print("native tag identity controls: 6 passed (wrong object, missing object and same-commit retag)")

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)
    for record in base["declarationRecords"]:
        target=root/record["path"];target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(audit.ROOT/record["path"],target)
    record=root/"inst/VENDORED.json";data=json.loads(record.read_text())
    data["draft_vectors"]["manifest_sha256"]="0"*64;record.write_text(json.dumps(data))
    try: audit.inventory(root)
    except ValueError as error: assert "manifest checksum disagree" in str(error)
    else: raise AssertionError("native manifest checksum disagreement was hidden")
    shutil.copyfile(audit.ROOT/"inst/VENDORED.json",record)
    record=root/"tests/draft/fhgm/provenance.json";data=json.loads(record.read_text())
    data["baseSchema"]["sha256"]="0"*64;record.write_text(json.dumps(data))
    changed=audit.inventory(root)
    assert next(r for r in changed["references"] if r["id"]=="fhgm-baseSchema")["files"][0]["sha256"]=="0"*64
    data=json.loads((root/"inst/VENDORED.json").read_text());data["files"][0]["commit"]="0"*40
    (root/"inst/VENDORED.json").write_text(json.dumps(data));changed=audit.inventory(root)
    assert next(r for r in changed["references"] if r["id"]=="vendored-0")["tagObject"]=="0"*40
print("R declaration controls: manifest mismatch refused, suite bases dynamic, native tag object preserved")
