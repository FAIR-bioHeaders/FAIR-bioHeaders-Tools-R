#!/usr/bin/env python3
# MPL-2.0. Native declarations -> shared immutable advisory checker, no re-pin.
import argparse, hashlib, json, os, re, subprocess, sys, tempfile
from pathlib import Path, PurePosixPath
ROOT = Path(__file__).resolve().parents[1]
CONSUMER = "FAIR-bioHeaders/FAIR-bioHeaders-Tools-R"
RECORD = 'inst/VENDORED.json'
AUTHORITY = "FAIR-bioHeaders/FAIR-bioHeaders-Specification"
def digest(data): return hashlib.sha256(data).hexdigest()
def relative(value):
    p = PurePosixPath(value)
    if not value or p.is_absolute() or ".." in p.parts: raise ValueError("unsafe declaration path")
    return str(p)
def repository(value):
    value = value.removesuffix(".git").rstrip("/")
    for prefix in ("https://github.com/", "git@github.com:"):
        if value.startswith(prefix): value = value[len(prefix):]
    if "/" not in value: value = "FAIR-bioHeaders/" + value
    if value in ("FAIR-bioHeaders/FHGM",): value = "FAIR-bioHeaders/FHGM-Specification"
    if value not in (AUTHORITY,"FAIR-bioHeaders/FHT-Specification","FAIR-bioHeaders/FHGM-Specification"):
        raise ValueError("unexpected declared authority: " + value)
    return value

def inventory(root=ROOT):
    refs, records = [], []
    def load(p):
        raw = (root / p).read_bytes(); records.append({"path":p,"sha256":digest(raw)})
        return json.loads(raw)
    revisions = load("references/authority-revisions.json")
    def add(identifier, repo, revision, commit, kind, files, material="released", native_tag_object=False, **extra):
        repo = repository(repo)
        tag = bool(re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", revision or ""))
        # Recorded annotated tag OBJECTS remain in native provenance. Their
        # separately reviewed dereferenced commit is metadata, never a pin move.
        if tag and native_tag_object:
            extra.update(tagObject=commit,requiresTagObject=True)
            commit=revisions.get(repo,{}).get(revision)
        elif tag and not commit:
            commit=revisions.get(repo,{}).get(revision)
        refs.append(dict(id=identifier, consumer=CONSUMER, repository=repo, revision=revision,
            revisionKind="tag" if tag else "commit", commit=commit, **{"class":kind},
            materialStatus=material, files=files, **extra))
    def file(local, source, sha):
        return {"local":relative(local) if local else None,"path":relative(source) if source else None,"sha256":sha}
    data = load("inst/VENDORED.json")
    for n,row in enumerate(data["files"]):
        kind = "draft-contract" if "draft" in row.get("kind","") else "released-contract"
        add("vendored-"+str(n),row["repository"],row["ref"] if kind=="released-contract" else row["commit"],row["commit"],kind,
            [file(row["file"],row.get("source_path"),row.get("sha256"))],"draft" if kind=="draft-contract" else "released", native_tag_object=kind=="released-contract")
    for name in ("conformance","draft_vectors","draft_fhgm_vectors"):
        row=data[name]; dest=row.get("dest", "tests/conformance" if name=="conformance" else None)
        if row["per_file"].get("manifest.json") != row.get("manifest_sha256"):
            raise ValueError("suite per-file and native manifest checksum disagree: "+name)
        add(name,row["repository"],row["ref"] if name=="conformance" else row["commit"],row["commit"],"conformance-suite",
            [file(dest+"/"+p,row["path"]+"/"+p,sha) for p,sha in row["per_file"].items()],"released" if name=="conformance" else "draft", localTree=dest, native_tag_object=name=="conformance")
        if row.get("examples_sha256"):
            add(name+"-examples",row["repository"],row["commit"],row["commit"],"copied-tree",
                [file(row["examples_dir"]+"/"+p,"development/examples/"+p,sha) for p,sha in row["examples_sha256"].items()],"draft")
    suite_provenance=load("tests/draft/fhgm/provenance.json")
    for name in ("baseSchema","matrixBaseSchema"):
        base=suite_provenance[name]
        installed=[r for r in data["files"] if r.get("header_type")=="FHGFF3" and r.get("ref")==base.get("ref")]
        if len(installed)!=1: raise ValueError("suite base has no unique declared installed copy: "+name)
        add("fhgm-"+name,base["repository"],base.get("ref"),base.get("commit"),"base-carrier",
            [file(installed[0]["file"],base.get("path"),base.get("sha256"))],tagObject=base.get("tagObject"),requiresTagObject=True)
    policy=load("references/reader-policy.json")
    add("reader-policy",policy["repository"],policy["commit"],policy["commit"],"conformance-suite",
        [file(f.get("local"),f.get("path"),f.get("sha256")) for f in policy["files"]],"draft")
    return {"inventoryVersion":1,"advisory":True,"declarationRecords":records,"references":refs,"coverageGaps":[
        {"scope":"Local generated R/C runtime, source history and historical previous receipts","disposition":"not cross-repository byte-copied contracts; existing native provenance checks retained"}]}

def verify_checker(checkout, metadata):
    checkout = checkout.resolve()
    if (metadata["repository"] != AUTHORITY
            or metadata["path"] != "scripts/check_references.py"
            or not re.fullmatch(r"[0-9a-f]{40}", metadata["commit"])
            or not re.fullmatch(r"[0-9a-f]{64}", metadata["sha256"])):
        raise ValueError("invalid checker source pin")
    environment = {**os.environ, "GIT_NO_REPLACE_OBJECTS": "1", "GIT_NO_LAZY_FETCH": "1", "GIT_TERMINAL_PROMPT": "0"}
    head = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], env=environment).decode().strip()
    if head != metadata["commit"]:
        raise ValueError("checker checkout HEAD does not match the declared source commit")
    name = relative(metadata["path"])
    source = checkout / name
    if source.resolve() != source:
        raise ValueError("checker source path must not traverse symlinks")
    raw = source.read_bytes()
    immutable = subprocess.check_output(["git", "-C", str(checkout), "show", f"{head}:{name}"], env=environment)
    if source.is_symlink() or raw != immutable or digest(raw) != metadata["sha256"]:
        raise ValueError("checker file does not match its immutable source/digest")
    return immutable



def tag_identity_findings(table, mappings):
    """Verify recorded native annotated-tag objects independently of tag commits."""
    import urllib.request, urllib.error
    checkouts = dict(value.split("=",1) for value in mappings)
    out = {}
    for row in table["references"]:
        if "tagObject" not in row and not row.get("requiresTagObject"): continue
        expected = row.get("tagObject")
        if not isinstance(expected,str) or not re.fullmatch(r"[0-9a-f]{40}",expected):
            out[row["id"]] = {"verdict":"ABSENT","reason":"native annotated-tag object is absent or malformed"}
            continue
        try:
            repo,tag=row["repository"],row["revision"]
            if repo in checkouts:
                env={**os.environ,"GIT_NO_REPLACE_OBJECTS":"1","GIT_NO_LAZY_FETCH":"1","GIT_TERMINAL_PROMPT":"0"}
                command=["git","-C",str(Path(checkouts[repo]).resolve()),"rev-parse","--verify"]
                control=subprocess.run(command+["refs/tags/__fair_bioheaders_missing_tag_control__"],env=env,capture_output=True)
                if control.returncode==0: raise RuntimeError("native tag negative control unexpectedly resolved")
                actual=subprocess.check_output(command+["refs/tags/"+tag],env=env,stderr=subprocess.PIPE).decode().strip()
            else:
                def get_tag(name):
                    request=urllib.request.Request("https://api.github.com/repos/"+repo+"/git/ref/tags/"+name,headers={"Accept":"application/vnd.github+json"})
                    token=os.environ.get("GITHUB_TOKEN")
                    if token: request.add_header("Authorization","Bearer "+token)
                    with urllib.request.urlopen(request,timeout=30) as response: return json.load(response)
                try: get_tag("__fair_bioheaders_missing_tag_control__")
                except urllib.error.HTTPError as error:
                    if error.code!=404: raise
                else: raise RuntimeError("native tag negative control unexpectedly resolved")
                actual=get_tag(tag)["object"]["sha"]
            if not re.fullmatch(r"[0-9a-f]{40}",actual): raise RuntimeError("empty/invalid native tag object measurement")
            out[row["id"]]={"verdict":"FRESH" if actual==expected else "DRIFT", "nativeTagObject":expected,"measuredTagObject":actual,"negativeControl":"confirmed-missing"}
        except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as error:
            out[row["id"]]={"verdict":"QUERY_FAILED","reason":"native tag object could not be verified: "+str(error)}
    return out

def audit(checkout, mappings=(), root=ROOT, strict=False):
    metadata = json.loads((root / "references/checker.json").read_text())
    checker_bytes = verify_checker(checkout, metadata)
    table = inventory(root)
    with tempfile.TemporaryDirectory(prefix="native-declared-references-") as work:
        generated = Path(work) / "inventory.json"
        generated.write_text(json.dumps(table, indent=2) + "\n")
        checker = Path(work) / "verified_check_references.py"
        checker.write_bytes(checker_bytes)
        checker.chmod(0o400)
        command = [sys.executable, "-I", str(checker), "--inventory", str(generated),
                   "--consumer", CONSUMER, "--consumer-root", str(root.resolve())]
        for mapping in mappings:
            command.extend(["--checkout", mapping])
        # Isolated Python does not import neighboring unverified helper modules.
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        raise RuntimeError("verified checker failed to produce an advisory report: " + result.stderr.strip())
    report = json.loads(result.stdout)
    if len(report.get("references", [])) != len(table["references"]):
        raise RuntimeError("checker did not report every declared reference group")
    native_tags=tag_identity_findings(table,mappings)
    for row in report["references"]:
        if row["id"] in native_tags:
            finding=native_tags[row["id"]]
            row["nativeTagIdentity"]=finding
            if finding["verdict"]!="FRESH": row["verdict"]=finding["verdict"]
    report.update(consumer=CONSUMER, checkerSource=metadata,
                  declarationRecords=table["declarationRecords"])
    return report, int(strict and any(row["verdict"] != "FRESH" for row in report["references"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checker-root", type=Path, required=True)
    parser.add_argument("--checkout", action="append", default=[], metavar="OWNER/REPO=PATH")
    parser.add_argument("--exit-on-findings", action="store_true", help="controlled offline check; scheduled audit stays advisory")
    parser.add_argument("--report-output", type=Path, help="atomic report outside the source checkout")
    args = parser.parse_args()
    if args.report_output:
        if args.report_output.resolve().is_relative_to(ROOT.resolve()):
            parser.error("report output must remain outside the source checkout")
        args.report_output.unlink(missing_ok=True)
    try:
        report, status = audit(args.checker_root, args.checkout, strict=args.exit_on_findings)
    except FileNotFoundError as exc:
        missing_declaration = bool(exc.filename) and Path(exc.filename).resolve() == (ROOT / RECORD).resolve()
        report = {"advisory": True, "wrote": [], "references": [{"id": "native-declarations",
                  "verdict": "ABSENT" if missing_declaration else "QUERY_FAILED",
                  "localComparison": "not-run", "reason": str(exc)}]}
        status = int(args.exit_on_findings) if missing_declaration else 1
    except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.SubprocessError, RuntimeError) as exc:
        report = {"advisory": True, "wrote": [], "references": [{"id": "native-audit-bootstrap",
                  "verdict": "QUERY_FAILED", "localComparison": "not-run", "reason": str(exc)}]}
        status = 1
    text = json.dumps(report, indent=2) + "\n"
    if args.report_output:
        args.report_output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=args.report_output.parent, delete=False) as stream:
            stream.write(text)
            temporary = Path(stream.name)
        temporary.replace(args.report_output)
    print(text, end="")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
