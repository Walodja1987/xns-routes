/**
 * Post-process docs/API.md after solidity-docgen:
 * 1. Remove the NatSpec note explaining the AT placeholder.
 * 2. Replace ` AT ` with `@` so generated docs use the canonical XNS separator.
 *
 * Run automatically via `docs:generate` / `compile:hh`.
 */

const fs = require("fs");
const path = require("path");

const API_MD = path.join(__dirname, "..", "..", "docs", "API.md");

const AT_NOTE =
  "The comments use AT instead of @ as solc treats @ as a documentation tag in NatSpec.";

function fixApiMarkdown(markdown) {
  let out = markdown;

  // Docgen italicizes @dev content as _..._ — strip both plain and italic forms.
  const notePatterns = [
    new RegExp(`_\\s*${escapeRegExp(AT_NOTE)}\\s*_\\s*\\n?`, "g"),
    new RegExp(`${escapeRegExp(AT_NOTE)}\\s*\\n?`, "g"),
  ];

  for (const pattern of notePatterns) {
    out = out.replace(pattern, "");
  }

  // Collapse accidental blank runs left after removing the note.
  out = out.replace(/\n{3,}/g, "\n\n");

  // Canonical XNS separator: spaced AT placeholder → @
  out = out.replace(/ AT /g, "@");

  return out;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function main() {
  if (!fs.existsSync(API_MD)) {
    throw new Error(`Missing ${API_MD}. Run hardhat docgen first.`);
  }

  const before = fs.readFileSync(API_MD, "utf8");
  const after = fixApiMarkdown(before);

  if (after === before) {
    console.log("docs/API.md: no AT placeholder changes needed.");
    return;
  }

  fs.writeFileSync(API_MD, after, "utf8");
  console.log("docs/API.md: replaced AT with @ and removed NatSpec AT note.");
}

main();
