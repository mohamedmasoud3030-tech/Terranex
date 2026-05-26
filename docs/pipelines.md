# Terranex Pipelines

Terranex can use batch pipelines to analyze repositories, documents, records, and operational data.

## Standard stages

- acquire: collect raw input
- prepare: create prompts or normalized inputs
- process: run analysis
- parse: convert output into structured data
- render: create reports

## First pipeline candidate

GitHub Issues Analyzer:

- Input: GitHub repository issues
- Output: HTML report and CSV summary
- Use case: classify issues by type, priority, urgency, summary, actions, and reasoning

## Notes

Pipeline runtime folders such as data and output are generated artifacts and should not be treated as source documents.
