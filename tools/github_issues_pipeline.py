"""
GitHub Issues Analyzer Pipeline
================================
Fetches issues from a GitHub repository, classifies each one by type and priority,
and renders an HTML report + CSV summary.

Usage:
    python tools/github_issues_pipeline.py acquire --batch-id 2026-05-26 --repo owner/repo --limit 10
    python tools/github_issues_pipeline.py prepare --batch-id 2026-05-26
    python tools/github_issues_pipeline.py estimate --batch-id 2026-05-26
    python tools/github_issues_pipeline.py process --batch-id 2026-05-26 --workers 5
    python tools/github_issues_pipeline.py parse --batch-id 2026-05-26
    python tools/github_issues_pipeline.py render --batch-id 2026-05-26
    python tools/github_issues_pipeline.py all --batch-id 2026-05-26 --repo owner/repo
    python tools/github_issues_pipeline.py clean --batch-id 2026-05-26 --clean-stage process
"""

import argparse
import csv
import html as html_lib
import json
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from datetime import date
from pathlib import Path
from typing import Any

import anthropic
import requests

DATA_DIR = Path("data")
OUTPUT_DIR = Path("output")

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
MODEL = "claude-sonnet-4-5-20251001"

PROMPT_TEMPLATE = """You are a senior engineering lead triaging GitHub issues.
Analyze the issue below and respond in exactly this format.

## Classification
Type: [bug/feature/question/docs/chore]

## Priority
Score: [1-10]
Urgency: [low/medium/high/critical]

## Summary
[1-2 sentences describing the issue in plain language]

## Recommended Action
- [Action item 1]
- [Action item 2]

## Reasoning
[Brief explanation of your classification and priority decision]

Follow this format exactly because I will be parsing it programmatically.

---

# Issue #{number}: {title}

**Labels:** {labels}
**State:** {state}
**Created:** {created_at}
**Author:** {author}

## Body
{body}
"""


@dataclass
class Item:
    id: str
    number: int
    title: str
    body: str
    labels: list[str]
    state: str
    created_at: str
    author: str
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class ParsedResult:
    issue_type: str = ""
    priority_score: int | None = None
    urgency: str = ""
    summary: str = ""
    recommended_actions: list[str] = field(default_factory=list)
    reasoning: str = ""
    parse_errors: list[str] = field(default_factory=list)


def get_batch_dir(batch_id: str) -> Path:
    return DATA_DIR / batch_id


def get_item_dir(batch_id: str, item_id: str) -> Path:
    return get_batch_dir(batch_id) / item_id


def get_output_dir(batch_id: str) -> Path:
    return OUTPUT_DIR / batch_id


def write_json_atomic(path: Path, value: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def write_text_atomic(path: Path, value: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(value, encoding="utf-8")
    tmp.replace(path)


def stage_acquire(batch_id: str, repo: str, limit: int | None = None) -> list[Path]:
    batch_dir = get_batch_dir(batch_id)
    batch_dir.mkdir(parents=True, exist_ok=True)

    items = fetch_items_from_source(repo, limit)
    acquired: list[Path] = []

    for item in items:
        item_dir = get_item_dir(batch_id, item.id)
        item_dir.mkdir(exist_ok=True)
        raw_file = item_dir / "raw.json"

        if raw_file.exists():
            print(f"Cached: {item.id}")
        else:
            write_json_atomic(raw_file, asdict(item))
            print(f"Acquired: {item.id} - {item.title[:60]}")

        acquired.append(item_dir)

    print(f"\nAcquire complete. {len(items)} issues in {batch_dir}")
    return acquired


def fetch_items_from_source(repo: str, limit: int | None = None) -> list[Item]:
    headers = {"Accept": "application/vnd.github+json"}
    if GITHUB_TOKEN:
        headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"

    items: list[Item] = []
    page = 1

    while True:
        url = f"https://api.github.com/repos/{repo}/issues"
        resp = requests.get(
            url,
            headers=headers,
            params={"state": "open", "per_page": 100, "page": page},
            timeout=30,
        )
        resp.raise_for_status()
        batch = resp.json()

        if not batch:
            break

        for issue in batch:
            if "pull_request" in issue:
                continue

            number = int(issue["number"])
            item_id = f"issue-{number:04d}"
            items.append(
                Item(
                    id=item_id,
                    number=number,
                    title=issue.get("title", ""),
                    body=(issue.get("body") or "")[:4000],
                    labels=[label["name"] for label in issue.get("labels", [])],
                    state=issue.get("state", ""),
                    created_at=issue.get("created_at", ""),
                    author=issue.get("user", {}).get("login", "unknown"),
                    metadata={"url": issue.get("html_url", "")},
                )
            )

            if limit and len(items) >= limit:
                return items[:limit]

        page += 1
        time.sleep(0.5)

    return items[:limit] if limit else items


def stage_prepare(batch_id: str) -> int:
    batch_dir = get_batch_dir(batch_id)
    prepared = 0

    for item_dir in sorted(batch_dir.iterdir()):
        if not item_dir.is_dir():
            continue

        raw_file = item_dir / "raw.json"
        prompt_file = item_dir / "prompt.md"

        if not raw_file.exists():
            continue
        if prompt_file.exists():
            print(f"Cached: {item_dir.name}")
            continue

        data: dict[str, Any] = json.loads(raw_file.read_text(encoding="utf-8"))
        prompt = PROMPT_TEMPLATE.format(
            number=data.get("number", "?"),
            title=data.get("title", ""),
            labels=", ".join(data.get("labels", [])) or "none",
            state=data.get("state", ""),
            created_at=data.get("created_at", ""),
            author=data.get("author", ""),
            body=data.get("body", "") or "(no description provided)",
        )

        write_text_atomic(prompt_file, prompt)
        prepared += 1
        print(f"Prepared: {item_dir.name}")

    print(f"\nPrepare complete. {prepared} prompts written.")
    return prepared


def stage_process(batch_id: str, model: str = MODEL, max_workers: int = 5) -> list[tuple[str, int, str | None]]:
    batch_dir = get_batch_dir(batch_id)
    to_process: list[tuple[Path, str]] = []

    for item_dir in sorted(batch_dir.iterdir()):
        if not item_dir.is_dir():
            continue
        prompt_file = item_dir / "prompt.md"
        response_file = item_dir / "response.md"
        if prompt_file.exists() and not response_file.exists():
            to_process.append((item_dir, prompt_file.read_text(encoding="utf-8")))

    if not to_process:
        print("No items to process.")
        return []

    print(f"Processing {len(to_process)} issues with {max_workers} workers...")
    client = anthropic.Anthropic()
    results: list[tuple[str, int, str | None]] = []

    def process_one(args: tuple[Path, str]) -> tuple[str, int, str | None]:
        item_dir, prompt = args
        response_file = item_dir / "response.md"
        try:
            message = client.messages.create(
                model=model,
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )
            response = message.content[0].text
            write_text_atomic(response_file, response)
            return (item_dir.name, len(response), None)
        except Exception as exc:
            return (item_dir.name, 0, str(exc))

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_one, item): item for item in to_process}
        for future in as_completed(futures):
            item_id, chars, error = future.result()
            results.append((item_id, chars, error))
            if error:
                print(f"  {item_id}: ERROR - {error}")
            else:
                print(f"  {item_id}: Done ({chars} chars)")

    print(f"\nProcess complete. {len(results)} issues processed.")
    return results


def stage_parse(batch_id: str) -> list[dict[str, Any]]:
    batch_dir = get_batch_dir(batch_id)
    all_results: list[dict[str, Any]] = []

    for item_dir in sorted(batch_dir.iterdir()):
        if not item_dir.is_dir():
            continue

        response_file = item_dir / "response.md"
        parsed_file = item_dir / "parsed.json"
        raw_file = item_dir / "raw.json"

        if not response_file.exists():
            continue

        response = response_file.read_text(encoding="utf-8")
        result = parse_response(response)

        meta: dict[str, Any] = {}
        if raw_file.exists():
            raw = json.loads(raw_file.read_text(encoding="utf-8"))
            meta = {
                "number": raw.get("number"),
                "title": raw.get("title", ""),
                "url": raw.get("metadata", {}).get("url", ""),
                "author": raw.get("author", ""),
                "labels": raw.get("labels", []),
            }

        write_json_atomic(parsed_file, asdict(result))
        all_results.append({"id": item_dir.name, **meta, **asdict(result)})

        errors = len(result.parse_errors)
        print(f"Parsed: {item_dir.name} (type={result.issue_type}, score={result.priority_score}, errors={errors})")

    agg_file = batch_dir / "all_results.json"
    write_json_atomic(agg_file, all_results)

    print(f"\nParse complete. {len(all_results)} results -> {agg_file}")
    return all_results


def parse_response(text: str) -> ParsedResult:
    result = ParsedResult()

    try:
        raw_type = extract_field(text, "Type") or ""
        valid_types = {"bug", "feature", "question", "docs", "chore"}
        result.issue_type = raw_type.lower() if raw_type.lower() in valid_types else raw_type.lower()
    except Exception as exc:
        result.parse_errors.append(f"Type: {exc}")

    try:
        result.priority_score = extract_score(text, "Score", 1, 10)
    except Exception as exc:
        result.parse_errors.append(f"Score: {exc}")

    try:
        raw_urgency = extract_field(text, "Urgency") or ""
        valid_urgency = {"low", "medium", "high", "critical"}
        result.urgency = raw_urgency.lower() if raw_urgency.lower() in valid_urgency else raw_urgency.lower()
    except Exception as exc:
        result.parse_errors.append(f"Urgency: {exc}")

    try:
        result.summary = extract_section(text, "Summary") or ""
    except Exception as exc:
        result.parse_errors.append(f"Summary: {exc}")

    try:
        result.recommended_actions = extract_list_items(text, "Recommended Action")
    except Exception as exc:
        result.parse_errors.append(f"Actions: {exc}")

    try:
        result.reasoning = extract_section(text, "Reasoning") or ""
    except Exception as exc:
        result.parse_errors.append(f"Reasoning: {exc}")

    return result


def extract_section(text: str, section_name: str) -> str | None:
    pattern = rf"(?:^|\n)(?:#+ *)?{re.escape(section_name)}[:\s]*\n(.*?)(?=\n#|\Z)"
    match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
    return match.group(1).strip() if match else None


def extract_field(text: str, field_name: str) -> str | None:
    pattern = rf"(?:\*\*)?{re.escape(field_name)}(?:\*\*)?[\s:\-]+([^\n]+)"
    match = re.search(pattern, text, re.IGNORECASE)
    return match.group(1).strip() if match else None


def extract_list_items(text: str, section_name: str) -> list[str]:
    section = extract_section(text, section_name)
    if not section:
        return []
    return [item.strip() for item in re.findall(r"^[\-\*]\s*(.+)$", section, re.MULTILINE)]


def extract_score(text: str, field_name: str, min_val: int, max_val: int) -> int | None:
    raw = extract_field(text, field_name)
    if not raw:
        return None
    match = re.search(r"\d+", raw)
    if not match:
        return None
    return max(min_val, min(max_val, int(match.group())))


URGENCY_COLOR = {
    "critical": "#dc2626",
    "high": "#ea580c",
    "medium": "#ca8a04",
    "low": "#16a34a",
    "": "#6b7280",
}

TYPE_EMOJI = {
    "bug": "bug",
    "feature": "feature",
    "question": "question",
    "docs": "docs",
    "chore": "chore",
    "": "item",
}


def stage_render(batch_id: str) -> Path | None:
    batch_dir = get_batch_dir(batch_id)
    output_dir = get_output_dir(batch_id)
    output_dir.mkdir(parents=True, exist_ok=True)

    results_file = batch_dir / "all_results.json"
    if not results_file.exists():
        print("No results to render. Run parse first.")
        return None

    results: list[dict[str, Any]] = json.loads(results_file.read_text(encoding="utf-8"))
    results.sort(key=lambda item: item.get("priority_score") or 0, reverse=True)

    html_file = output_dir / "index.html"
    write_text_atomic(html_file, render_html(results, batch_id))
    print(f"Rendered HTML: {html_file}")

    csv_file = output_dir / "results.csv"
    render_csv(results, csv_file)
    print(f"Rendered CSV: {csv_file}")

    return html_file


def render_html(results: list[dict[str, Any]], batch_id: str) -> str:
    rows = ""
    for item in results:
        urgency = item.get("urgency", "")
        color = URGENCY_COLOR.get(urgency, "#6b7280")
        label = TYPE_EMOJI.get(item.get("issue_type", ""), "item")
        url = html_lib.escape(item.get("url", "#"), quote=True)
        number = item.get("number", "")
        title = html_lib.escape(item.get("title", item.get("id", "")))
        actions = "".join(f"<li>{html_lib.escape(action)}</li>" for action in (item.get("recommended_actions") or []))

        rows += f"""
        <tr>
          <td><a href="{url}" target="_blank">#{number}</a></td>
          <td>{label}: {html_lib.escape(item.get('issue_type', ''))}</td>
          <td><strong>{item.get('priority_score', 'N/A')}</strong></td>
          <td style="color:{color};font-weight:600">{html_lib.escape(urgency.upper())}</td>
          <td>{title}</td>
          <td>{html_lib.escape(item.get('summary', '')[:120])}</td>
          <td><ul style="margin:0;padding-left:16px">{actions}</ul></td>
        </tr>"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>GitHub Issues - {html_lib.escape(batch_id)}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 1400px; margin: 0 auto; padding: 24px; background: #f9fafb; }}
    h1 {{ color: #111827; }}
    .meta {{ color: #6b7280; margin-bottom: 24px; }}
    table {{ width: 100%; border-collapse: collapse; background: white; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }}
    th {{ background: #1f2937; color: white; text-align: left; padding: 12px 16px; font-size: 13px; }}
    td {{ padding: 12px 16px; border-bottom: 1px solid #e5e7eb; vertical-align: top; font-size: 13px; }}
    tr:last-child td {{ border-bottom: none; }}
    tr:hover td {{ background: #f9fafb; }}
    a {{ color: #2563eb; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
  <h1>GitHub Issues Analysis</h1>
  <p class="meta">Batch: <strong>{html_lib.escape(batch_id)}</strong> - {len(results)} issues - sorted by priority</p>
  <table>
    <tr>
      <th>#</th><th>Type</th><th>Score</th><th>Urgency</th>
      <th>Title</th><th>Summary</th><th>Recommended Actions</th>
    </tr>
    {rows}
  </table>
</body>
</html>"""


def render_csv(results: list[dict[str, Any]], output_file: Path) -> None:
    tmp = output_file.with_suffix(output_file.suffix + ".tmp")
    with open(tmp, "w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=["id", "number", "title", "issue_type", "priority_score", "urgency", "summary", "author", "url"],
        )
        writer.writeheader()
        for item in results:
            writer.writerow({
                "id": item.get("id", ""),
                "number": item.get("number", ""),
                "title": item.get("title", ""),
                "issue_type": item.get("issue_type", ""),
                "priority_score": item.get("priority_score", ""),
                "urgency": item.get("urgency", ""),
                "summary": item.get("summary", ""),
                "author": item.get("author", ""),
                "url": item.get("url", ""),
            })
    tmp.replace(output_file)


def stage_clean(batch_id: str, from_stage: str | None = None) -> int:
    batch_dir = get_batch_dir(batch_id)
    if not batch_dir.exists():
        print(f"No data directory for {batch_id}")
        return 0

    stage_outputs = {
        "acquire": ["raw.json"],
        "prepare": ["prompt.md"],
        "process": ["response.md"],
        "parse": ["parsed.json"],
    }
    stage_order = ["acquire", "prepare", "process", "parse", "render"]
    start_idx = stage_order.index(from_stage) if from_stage else 0
    stages_to_clean = stage_order[start_idx:]

    files_to_delete: set[str] = set()
    for stage in stages_to_clean:
        files_to_delete.update(stage_outputs.get(stage, []))

    deleted = 0
    for item_dir in batch_dir.iterdir():
        if not item_dir.is_dir():
            continue
        for filename in files_to_delete:
            target = item_dir / filename
            if target.exists():
                target.unlink()
                deleted += 1

    if "parse" in stages_to_clean:
        agg = batch_dir / "all_results.json"
        if agg.exists():
            agg.unlink()
            deleted += 1

    print(f"Cleaned {deleted} files from stage '{from_stage or 'all'}' onwards.")
    return deleted


def stage_estimate(batch_id: str) -> dict[str, Any] | None:
    batch_dir = get_batch_dir(batch_id)
    if not batch_dir.exists():
        print(f"No data for {batch_id}. Run acquire first.")
        return None

    item_count = 0
    total_chars = 0
    for item_dir in batch_dir.iterdir():
        if not item_dir.is_dir():
            continue
        prompt_file = item_dir / "prompt.md"
        if prompt_file.exists():
            total_chars += len(prompt_file.read_text(encoding="utf-8"))
            item_count += 1

    if item_count == 0:
        print("No prompts found. Run prepare first.")
        return None

    est_input = int(total_chars / 4)
    est_output = item_count * 500
    cost = (est_input * 3.0 / 1_000_000) + (est_output * 15.0 / 1_000_000)

    estimate = {
        "batch_id": batch_id,
        "item_count": item_count,
        "est_input_tokens": est_input,
        "est_output_tokens": est_output,
        "est_cost_usd": round(cost, 4),
    }

    print(f"\nCost Estimate - {batch_id}")
    print(f"  Issues: {item_count}")
    print(f"  Input tokens: {est_input:,}")
    print(f"  Output tokens: {est_output:,}")
    print(f"  Estimated cost: ${cost:.4f}")
    print("  Add 20-30% buffer for retries.")
    return estimate


def main() -> None:
    parser = argparse.ArgumentParser(description="GitHub Issues Analyzer Pipeline")
    parser.add_argument("stage", choices=["acquire", "prepare", "process", "parse", "render", "all", "clean", "estimate"])
    parser.add_argument("--batch-id", default=None)
    parser.add_argument("--repo", default=None, help="GitHub repo, for example owner/repo")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--workers", type=int, default=5)
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--clean-stage", choices=["acquire", "prepare", "process", "parse"])
    args = parser.parse_args()

    batch_id = args.batch_id or date.today().isoformat()
    print(f"Batch ID: {batch_id}\n")

    if args.stage == "clean":
        stage_clean(batch_id, args.clean_stage)
    elif args.stage == "estimate":
        stage_estimate(batch_id)
    elif args.stage == "all":
        if not args.repo:
            parser.error("--repo required for 'all' stage")
        stage_acquire(batch_id, args.repo, args.limit)
        stage_prepare(batch_id)
        stage_estimate(batch_id)
        stage_process(batch_id, args.model, args.workers)
        stage_parse(batch_id)
        stage_render(batch_id)
    elif args.stage == "acquire":
        if not args.repo:
            parser.error("--repo required for acquire stage")
        stage_acquire(batch_id, args.repo, args.limit)
    elif args.stage == "prepare":
        stage_prepare(batch_id)
    elif args.stage == "process":
        stage_process(batch_id, args.model, args.workers)
    elif args.stage == "parse":
        stage_parse(batch_id)
    elif args.stage == "render":
        stage_render(batch_id)


if __name__ == "__main__":
    main()
