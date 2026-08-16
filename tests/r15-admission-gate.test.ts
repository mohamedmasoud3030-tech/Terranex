import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

const sourceGate = resolve("scripts/check-r15-admission.mjs");
const workspaces: string[] = [];

function decisionId(index: number) {
  return `BD-${String(index).padStart(3, "0")}`;
}

function completeRecord(id: string) {
  return [
    `Decision ID: ${id}`,
    "Status: RESOLVED",
    "Decision date: 2026-08-17",
    "Decision owner: Authorized Owner",
    "Business decision: Explicit approved rule",
    "Applies to: organization",
    "Effective date or version: 2026-08-17",
    "Business evidence/reference: OWNER-DECISION-REF",
    "Accounting review required? yes/no + reference: no — not required for this test fixture",
    "Legal review required? yes/no + reference: no — not required for this test fixture",
    "Affected canonical docs/ADRs: docs/OPEN_BUSINESS_DECISIONS.md",
    "Implementation explicitly authorized: bounded test behavior",
    "Still deferred / not implied: all behavior outside the bounded decision",
  ].join("\n");
}

function makeRegister({
  status = "RESOLVED",
  placeholderDecisionDate = false,
  duplicateStatusFor,
  duplicateRecordFor,
  duplicateFieldFor,
  leakLastRecordFieldFromTail = false,
}: {
  status?: "OPEN" | "RESOLVED";
  placeholderDecisionDate?: boolean;
  duplicateStatusFor?: string;
  duplicateRecordFor?: string;
  duplicateFieldFor?: string;
  leakLastRecordFieldFromTail?: boolean;
} = {}) {
  const rows = Array.from({ length: 12 }, (_, offset) => {
    const id = decisionId(offset + 1);
    return `| ${id} | ${status} | decision | blocks |`;
  });

  if (duplicateStatusFor) {
    rows.push(`| ${duplicateStatusFor} | ${status} | duplicate | blocks |`);
  }

  const records =
    status === "RESOLVED"
      ? Array.from({ length: 12 }, (_, offset) => {
          const id = decisionId(offset + 1);
          let record = completeRecord(id);
          if (placeholderDecisionDate && id === "BD-001") {
            record = record.replace(
              "Decision date: 2026-08-17",
              "Decision date: <YYYY-MM-DD>",
            );
          }
          if (duplicateFieldFor === id) {
            record += "\nBusiness decision: conflicting duplicate rule";
          }
          if (leakLastRecordFieldFromTail && id === "BD-012") {
            record = record.replace("Decision date: 2026-08-17\n", "");
          }
          return record;
        })
      : [];

  if (duplicateRecordFor) {
    records.push(completeRecord(duplicateRecordFor));
  }

  const sections = ["# Test decision register", ...rows, "", ...records];
  if (leakLastRecordFieldFromTail) {
    sections.push("# Unrelated appendix\nDecision date: 2026-08-18");
  }

  return sections.join("\n\n");
}

function runGate(register: string) {
  const root = mkdtempSync(join(tmpdir(), "terranex-r15-gate-"));
  workspaces.push(root);
  const scriptsDir = join(root, "scripts");
  const docsDir = join(root, "docs");
  mkdirSync(scriptsDir);
  mkdirSync(docsDir);
  copyFileSync(sourceGate, join(scriptsDir, "check-r15-admission.mjs"));
  writeFileSync(join(docsDir, "OPEN_BUSINESS_DECISIONS.md"), register);

  return spawnSync(process.execPath, [join(scriptsDir, "check-r15-admission.mjs")], {
    encoding: "utf8",
  });
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop();
    if (workspace) rmSync(workspace, { recursive: true, force: true });
  }
});

describe("R15 admission gate", () => {
  it("blocks while any canonical decision remains OPEN", () => {
    const result = runGate(makeRegister({ status: "OPEN" }));

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("R15 admission: BLOCKED");
    expect(result.stderr).toContain("BD-001: status is OPEN, not RESOLVED");
    expect(result.stderr).toContain("BD-012: status is OPEN, not RESOLVED");
  });

  it("passes only with one complete RESOLVED record per decision", () => {
    const result = runGate(makeRegister());

    expect(result.status).toBe(0);
    expect(result.stdout).toContain("R15 admission: PASS");
    expect(result.stderr).toBe("");
  });

  it("rejects placeholder values in required evidence fields", () => {
    const result = runGate(makeRegister({ placeholderDecisionDate: true }));

    expect(result.status).toBe(1);
    expect(result.stderr).toContain(
      "BD-001: resolution record field 'Decision date' is missing or empty",
    );
  });

  it("rejects duplicate canonical status rows", () => {
    const result = runGate(makeRegister({ duplicateStatusFor: "BD-006" }));

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("BD-006: canonical status row is duplicated");
  });

  it("rejects duplicate resolution records", () => {
    const result = runGate(makeRegister({ duplicateRecordFor: "BD-012" }));

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("BD-012: resolution record is duplicated");
  });

  it("does not satisfy a missing BD-012 field from unrelated trailing content", () => {
    const result = runGate(makeRegister({ leakLastRecordFieldFromTail: true }));

    expect(result.status).toBe(1);
    expect(result.stderr).toContain(
      "BD-012: resolution record field 'Decision date' is missing or empty",
    );
  });

  it("rejects duplicate fields inside one resolution record", () => {
    const result = runGate(makeRegister({ duplicateFieldFor: "BD-004" }));

    expect(result.status).toBe(1);
    expect(result.stderr).toContain(
      "BD-004: resolution record field 'Business decision' is duplicated",
    );
  });
});
