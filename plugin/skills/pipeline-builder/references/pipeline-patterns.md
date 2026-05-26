# Pipeline Patterns

## Stages

- acquire
- prepare
- process
- parse
- render

## Reliability notes

- prefer atomic writes
- preserve intermediate outputs
- support reruns
- isolate outputs per item
- keep parsing deterministic

## Typical outputs

- html reports
- csv exports
- parsed json
- markdown summaries
