---
name: pipeline-builder
description: >
  Build reusable acquire/prepare/process/parse/render pipelines for Terranex analysis and automation workflows.
---

# Pipeline Builder

This skill defines the standard Terranex pipeline architecture.

## Standard stages

1. acquire
2. prepare
3. process
4. parse
5. render

## Expected characteristics

- deterministic stage boundaries
- cached outputs
- atomic writes
- parallel processing only for expensive model stages
- structured parsing
- HTML and CSV reporting support

## Typical Terranex use cases

- GitHub repository analysis
- contract analysis
- invoice extraction
- transaction classification
- operational document review
- partner statement generation
- profitability analysis

## Current implementation

Reference implementation:

```text
tools/github_issues_pipeline.py
```
