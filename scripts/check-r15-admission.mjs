import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const registerPath = resolve(here, "../docs/OPEN_BUSINESS_DECISIONS.md");
const register = readFileSync(registerPath, "utf8");

const decisionIds = Array.from({ length: 12 }, (_, index) =>
  `BD-${String(index + 1).padStart(3, "0")}`,
);

const requiredFields = [
  "Decision date",
  "Decision owner",
  "Business decision",
  "Applies to",
  "Effective date or version",
  "Business evidence/reference",
  "Accounting review required? yes/no + reference",
  "Legal review required? yes/no + reference",
  "Affected canonical docs/ADRs",
  "Implementation explicitly authorized",
  "Still deferred / not implied",
];

const errors = [];

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isMeaningful(value) {
  const normalized = value.trim();
  if (!normalized) return false;
  if (/^<[^>]+>$/.test(normalized)) return false;
  if (/^[_\-–—.]+$/.test(normalized)) return false;
  return !/^(tbd|todo|pending|unknown|unset)$/i.test(normalized);
}

for (const id of decisionIds) {
  const rowPattern = new RegExp(
    `^\\|\\s*${escapeRegExp(id)}\\s*\\|\\s*(OPEN|RESOLVED)\\s*\\|`,
    "gm",
  );
  const rowMatches = [...register.matchAll(rowPattern)];

  if (rowMatches.length === 0) {
    errors.push(`${id}: canonical status row is missing or malformed.`);
    continue;
  }

  if (rowMatches.length > 1) {
    errors.push(`${id}: canonical status row is duplicated.`);
    continue;
  }

  if (rowMatches[0][1] !== "RESOLVED") {
    errors.push(`${id}: status is ${rowMatches[0][1]}, not RESOLVED.`);
    continue;
  }

  const recordStartPattern = new RegExp(
    `^Decision ID:\\s*${escapeRegExp(id)}\\s*$`,
    "gm",
  );
  const recordStartMatches = [...register.matchAll(recordStartPattern)];

  if (recordStartMatches.length === 0) {
    errors.push(`${id}: RESOLVED row has no matching resolution record.`);
    continue;
  }

  if (recordStartMatches.length > 1) {
    errors.push(`${id}: resolution record is duplicated.`);
    continue;
  }

  const recordStartMatch = recordStartMatches[0];
  const recordStart = recordStartMatch.index;
  const remainder = register.slice(recordStart + recordStartMatch[0].length);
  const nextRecord = /^Decision ID:\s*BD-\d{3}\s*$/m.exec(remainder);
  const record = nextRecord
    ? register.slice(recordStart, recordStart + recordStartMatch[0].length + nextRecord.index)
    : register.slice(recordStart);

  if (!/^Status:\s*RESOLVED\s*$/m.test(record)) {
    errors.push(`${id}: resolution record must contain 'Status: RESOLVED'.`);
  }

  for (const field of requiredFields) {
    const fieldPattern = new RegExp(
      `^${escapeRegExp(field)}:\\s*(.+)$`,
      "m",
    );
    const fieldMatch = record.match(fieldPattern);
    if (!fieldMatch || !isMeaningful(fieldMatch[1])) {
      errors.push(`${id}: resolution record field '${field}' is missing or empty.`);
    }
  }
}

if (errors.length > 0) {
  console.error("R15 admission: BLOCKED");
  console.error(
    "R14 is not complete. Terranex must not activate target-company investor economics until all BD-001…BD-012 decisions are explicitly resolved and evidenced.\n",
  );
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  "R15 admission: PASS — BD-001…BD-012 are RESOLVED and each has one complete canonical resolution record.",
);
