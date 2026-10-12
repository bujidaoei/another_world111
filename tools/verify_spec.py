"""Validate Spec Kit document references and task-state consistency; never certify gameplay."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FEATURE = ROOT / "specs" / "001-project-foundation"
REQUIRED = (
    "spec.md", "plan.md", "tasks.md", "research.md", "research-design.md",
    "decisions.md", "data-model.md", "contracts/gameplay.md", "quickstart.md",
    "validation.md", "checklists/requirements.md", "progress.md", "analysis.md",
    "evidence/2026-10-13/tool-audit.md", "evidence/2026-10-13/speckit-audit.md",
)


def verify(source_request: Path | None) -> dict:
    errors: list[str] = []
    texts: dict[str, str] = {}
    for name in REQUIRED:
        path = FEATURE / name
        if not path.is_file():
            errors.append(f"Missing document: {name}")
        else:
            texts[name] = path.read_text(encoding="utf-8-sig")
    record_path = FEATURE / "task-records.json"
    try:
        records = json.loads(record_path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        errors.append(f"Cannot read task records: {type(exc).__name__}")
        records = []
    spec = texts.get("spec.md", "")
    requirement_ids = re.findall(r"^- \*\*((?:REQ|NFR)-\d{3})\*\*", spec, re.MULTILINE)
    ac_ids = re.findall(r"^\| (AC-\d{3}) \|", spec, re.MULTILINE)
    for label, ids in (("requirements", requirement_ids), ("acceptance", ac_ids)):
        if len(ids) != len(set(ids)) or not ids:
            errors.append(f"Empty or duplicate {label} IDs")
    task_matches = re.findall(
        r"^- \[([ xX])\] (TASK-\d{3})\b", texts.get("tasks.md", ""), re.MULTILINE
    )
    tasks = {task_id: state.lower() == "x" for state, task_id in task_matches}
    if len(task_matches) != len(tasks):
        errors.append("Duplicate task checklist ID")
    task_ids = [record["id"] for record in records]
    if len(task_ids) != len(set(task_ids)) or set(task_ids) != set(tasks):
        errors.append("Task record/checklist IDs differ or repeat")
    covered: set[str] = set()
    protocols = set(re.findall(r"^\| (TEST-\d{3}) \|", texts.get("validation.md", ""), re.MULTILINE))
    for record in records:
        task_id = record["id"]
        if not record.get("path") or not record.get("criterion") or not record.get("status"):
            errors.append(f"Task metadata incomplete: {task_id}")
        covered.update(record["requirements"])
        if not set(record["requirements"]) <= set(requirement_ids):
            errors.append(f"Unknown requirement in {task_id}")
        if not set(record["acceptance"]) <= set(ac_ids):
            errors.append(f"Unknown acceptance in {task_id}")
        if not set(record["dependencies"]) <= set(task_ids):
            errors.append(f"Unknown dependency in {task_id}")
        if record["test"] not in protocols:
            errors.append(f"Missing verification protocol for {task_id}")
        if tasks.get(task_id) != record["done"]:
            errors.append(f"Task checkbox and record disagree: {task_id}")
        if record["done"]:
            if not record["status"].startswith("已验收") or not record["evidence"]:
                errors.append(f"Completed task lacks accepted status/evidence: {task_id}")
            for evidence in record["evidence"]:
                if not (FEATURE / evidence).is_file():
                    errors.append(f"Missing completion evidence for {task_id}: {evidence}")
            if any(not tasks.get(dep) for dep in record["dependencies"]):
                errors.append(f"Completed task has incomplete dependency: {task_id}")
    for missing in sorted(set(requirement_ids) - covered):
        errors.append(f"Requirement without any task: {missing}")
    visiting: set[str] = set()
    visited: set[str] = set()
    by_id = {record["id"]: record for record in records}

    def visit(task_id: str) -> None:
        if task_id in visiting:
            errors.append(f"Dependency cycle at {task_id}")
            return
        if task_id in visited or task_id not in by_id:
            return
        visiting.add(task_id)
        for dep in by_id[task_id]["dependencies"]:
            visit(dep)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in task_ids:
        visit(task_id)
    files = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout.decode("utf-8").split("\0")
    for name, body in texts.items():
        if re.search(r"\[NEEDS CLARIFICATION|\[PROJECT_NAME\]|\[FEATURE NAME\]|TKTK", body):
            errors.append(f"Unresolved template token in active document: {name}")
        for target in re.findall(r"(?<!!)\[[^\]\n]+\]\(([^)]+)\)", body):
            if target.startswith(("http://", "https://", "#")):
                continue
            resolved = (FEATURE / name).parent / target.split("#", 1)[0]
            if not resolved.exists():
                errors.append(f"Broken local link in {name}: {target}")
    secrets: list[str] = []
    if source_request is not None:
        source = source_request.read_text(encoding="utf-8-sig")
        secrets = re.findall(r"GitHub[^\r\n]*密码[：:]\s*\r?\n([^\r\n]+)", source)
        if not secrets:
            errors.append("Source request sensitive-field check did not find expected field")
    fingerprints: dict[str, str] = {}
    for name in sorted(set(files) - {""}):
        path = ROOT / name
        if "reference-" in path.name and path.suffix in (".png", ".jpg"):
            errors.append(f"Reference media would be versioned: {name}")
        if path.suffix.lower() in (".key", ".pem", ".keystore", ".jks"):
            errors.append(f"Private/signing file would be versioned: {name}")
        if path.is_file():
            content = path.read_bytes()
            if any(secret.strip().encode("utf-8") in content for secret in secrets):
                errors.append(f"Sensitive source content found in: {name}")
            if name.startswith(("specs/", "tools/", ".specify/memory/")) and not name.endswith(
                ("validation-result.json", "delivery.md")
            ):
                fingerprints[name] = hashlib.sha256(content).hexdigest()
    return {
        "kind": "phase0_document_consistency", "time": datetime.now(timezone(timedelta(hours=8), "Asia/Shanghai")).isoformat(),
        "requirements": len(requirement_ids), "acceptance_conditions": len(ac_ids), "tasks": len(task_ids),
        "completed_tasks": sum(record["done"] for record in records),
        "planned_verification_protocols": len(protocols), "game_tests_executed": 0,
        "source_sensitive_field_scanned": source_request is not None,
        "reference_media_excluded": not any("Reference media" in error for error in errors),
        "errors": errors, "passed": not errors, "fingerprints_sha256": fingerprints,
        "limitations": "Structural/reference/state checks only; not semantic, gameplay, device, visual, or human acceptance.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-request", type=Path, help="Check source password only in memory; never print it")
    parser.add_argument("--output", type=Path, help="Save JSON evidence")
    args = parser.parse_args()
    result = verify(args.source_request)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    summary = {key: value for key, value in result.items() if key != "fingerprints_sha256"}
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
