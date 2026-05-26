---
name: github-issues-analyzer
description: >
  Use this skill when Terranex needs to inspect GitHub issues for a repository,
  classify them by type and priority, and produce an HTML or CSV report.
---

# GitHub Issues Analyzer

This skill uses `tools/github_issues_pipeline.py` to run a repeatable five-stage batch pipeline over GitHub issues.

## When to use

Use it when the project needs to:

- Fetch open issues from a GitHub repository.
- Exclude pull requests from issue analysis.
- Classify issues as bug, feature, question, docs, or chore.
- Estimate priority score and urgency.
- Produce a report for planning or triage.

## Pipeline stages

| Stage | Purpose | Main output |
|---|---|---|
| acquire | Fetch GitHub issues | `data/{batch_id}/{issue_id}/raw.json` |
| prepare | Build issue prompts | `prompt.md` |
| estimate | Estimate token and cost | terminal output |
| process | Run model classification | `response.md` |
| parse | Extract structured results | `parsed.json`, `all_results.json` |
| render | Build reports | `output/{batch_id}/index.html`, `results.csv` |

## Quickstart

```bash
python tools/github_issues_pipeline.py acquire --batch-id 2026-05-26 --repo owner/repo --limit 10
python tools/github_issues_pipeline.py prepare --batch-id 2026-05-26
python tools/github_issues_pipeline.py estimate --batch-id 2026-05-26
python tools/github_issues_pipeline.py process --batch-id 2026-05-26 --workers 5
python tools/github_issues_pipeline.py parse --batch-id 2026-05-26
python tools/github_issues_pipeline.py render --batch-id 2026-05-26
```

## Notes

- Generated `data/` and `output/` folders are runtime artifacts.
- The pipeline supports cached stage outputs and selective cleaning.
- The pipeline can run end-to-end with the `all` stage.
