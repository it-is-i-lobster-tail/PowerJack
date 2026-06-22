/* global console, process */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";

/** @type {string[]} */
const requiredFiles = [
  "docs/ui-design-standards.md",
  "src/shared/styles/tokens.css",
  "docs/reference_images/MANIFEST.txt",
];

/** @type {RegExp[]} */
const uiPatterns = [
  /^AGENTS\.md$/,
  /^package\.json$/,
  /^docs\/ui-design-standards\.md$/,
  /^docs\/reference_images\//,
  /^src\/app\/.*\.(css|ts|tsx)$/,
  /^src\/features\/.*\.(css|ts|tsx)$/,
  /^src\/shared\/styles\/.*\.css$/,
  /^src\/shared\/ui\/.*\.(css|ts|tsx)$/,
  /^e2e\/.*\.(ts|tsx)$/,
];

/**
 * @param {string[]} args
 * @returns {string[]}
 */
function git(args) {
  try {
    return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * @param {string[]} values
 * @returns {string[]}
 */
function unique(values) {
  return [...new Set(values)].sort((a, b) => a.localeCompare(b));
}

const missingFiles = requiredFiles.filter((file) => !existsSync(file));

if (missingFiles.length > 0) {
  console.error("PowerJack UX Design Standards Check failed.");
  console.error("Missing required design standard files:");
  for (const file of missingFiles) {
    console.error(`- ${file}`);
  }
  process.exitCode = 1;
}

const changedFiles = unique([
  ...git(["diff", "--name-only"]),
  ...git(["diff", "--name-only", "--cached"]),
  ...git(["ls-files", "--others", "--exclude-standard"]),
]);

const uiFiles = changedFiles.filter((file) => uiPatterns.some((pattern) => pattern.test(file)));

console.log("PowerJack UX Design Standards Check");
console.log("");
console.log("Read before handoff:");
console.log("- docs/ui-design-standards.md");
console.log("- src/shared/styles/tokens.css");
console.log("- Relevant docs/reference_images/* files");
console.log("");

if (uiFiles.length > 0) {
  console.log("Likely UI-affecting changed files:");
  for (const file of uiFiles) {
    console.log(`- ${file}`);
  }
} else {
  console.log("No likely UI-affecting changed files detected.");
}

console.log("");
console.log("Agent pre-commit checklist:");
console.log("- Steel Focus palette and shared tokens are preserved.");
console.log("- Layout remains mobile-first, compact, and readable.");
console.log("- Workout logging stays dense: shared labels, horizontal set rows, no large card per set.");
console.log("- Selected, active, complete, disabled, locked, and error states are visible without relying on color alone.");
console.log("- Motion is short, causal, and does not delay logging.");
console.log("- Copy is short, calm, direct, and not gamified.");
console.log("- Controls keep accessible roles/names and stable data-agent-id selectors.");
console.log("- Browser/mobile visual QA and screenshot or E2E evidence are recorded when layout changes.");
console.log("- Any intentional standard deviation is explained in the handoff.");
