/* global console, process */

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

/** @type {string[]} */
const requiredFiles = [
  "docs/ui-design-standards.md",
  "docs/typography-standards.md",
  "src/shared/styles/tokens.css",
  "docs/reference_images/MANIFEST.txt",
];

/** @type {RegExp[]} */
const uiPatterns = [
  /^AGENTS\.md$/,
  /^package\.json$/,
  /^docs\/ui-design-standards\.md$/,
  /^docs\/typography-standards\.md$/,
  /^docs\/reference_images\//,
  /^\.codex\/skills\/powerjack-typography\//,
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

const typographyTokenValues = {
  "--font-size-header-1": "34px",
  "--font-size-header-2": "22px",
  "--font-size-sub-header": "16px",
  "--font-size-info": "13px",
};

const allowedFontSizeValues = new Set(Object.keys(typographyTokenValues).map((token) => `var(${token})`));

/**
 * @param {string[]} extensions
 * @returns {string[]}
 */
function sourceFiles(extensions) {
  return git(["ls-files", "src"]).filter((file) => extensions.some((extension) => file.endsWith(extension)));
}

/**
 * @param {string} file
 * @returns {{ line: string, lineNumber: number }[]}
 */
function readLines(file) {
  return readFileSync(file, "utf8")
    .split("\n")
    .map((line, index) => ({ line, lineNumber: index + 1 }));
}

/**
 * @param {string} value
 * @returns {boolean}
 */
function isApprovedFontSizeValue(value) {
  return allowedFontSizeValues.has(value.trim());
}

function findTypographyFindings() {
  /** @type {string[]} */
  const findings = [];
  const tokensCss = readFileSync("src/shared/styles/tokens.css", "utf8");
  const resetCss = readFileSync("src/shared/styles/reset.css", "utf8");

  for (const [token, value] of Object.entries(typographyTokenValues)) {
    if (!tokensCss.includes(`${token}: ${value};`)) {
      findings.push(`src/shared/styles/tokens.css: expected ${token}: ${value};`);
    }
  }

  if (!resetCss.includes("font-size: var(--font-size-sub-header);")) {
    findings.push("src/shared/styles/reset.css: body must set font-size: var(--font-size-sub-header);");
  }

  for (const selector of ["h1", "h2", "h3", "h4", "h5", "h6", "small", "legend"]) {
    if (!resetCss.includes(selector)) {
      findings.push(`src/shared/styles/reset.css: ${selector} must inherit tokenized app text sizing.`);
    }
  }

  for (const control of ["button", "input", "textarea", "select"]) {
    if (!resetCss.includes(control)) {
      findings.push(`src/shared/styles/reset.css: ${control} must inherit tokenized app text sizing.`);
    }
  }

  for (const file of sourceFiles([".css"])) {
    for (const { line, lineNumber } of readLines(file)) {
      const fontSizeMatch = line.match(/\bfont-size\s*:\s*([^;]+);/);

      if (fontSizeMatch) {
        const value = fontSizeMatch[1];

        if (line.includes("Typography exception")) {
          if (!/font-size\s*:\s*0\s*;/.test(line)) {
            findings.push(`${file}:${lineNumber}: Typography exception must be limited to font-size: 0;`);
          }
        } else if (!(file === "src/shared/styles/reset.css" && value.trim() === "inherit") && !isApprovedFontSizeValue(value)) {
          findings.push(`${file}:${lineNumber}: font-size must use a typography token, found ${value.trim()}`);
        }
      }

      const fontShorthandMatch = line.match(/(^|[;{\s])font\s*:\s*([^;]+);/);

      if (fontShorthandMatch && fontShorthandMatch[2].trim() !== "inherit") {
        findings.push(`${file}:${lineNumber}: font shorthand may only use inherit; use font-size tokens in CSS.`);
      }
    }
  }

  for (const file of sourceFiles([".ts", ".tsx"])) {
    for (const { line, lineNumber } of readLines(file)) {
      if (/\bfontSize\s*[:=]/.test(line) || /["']font-size["']\s*:/.test(line)) {
        findings.push(`${file}:${lineNumber}: inline fontSize is not allowed; use a typography token in CSS.`);
      }

      if (/style=\{\{[^}]*\bfont\b/.test(line) || /\bfont\s*:\s*["'`]/.test(line)) {
        findings.push(`${file}:${lineNumber}: inline font shorthand is not allowed; use CSS tokens.`);
      }

      if (/\.(fillText|strokeText|measureText)\s*\(|\.font\s*=/.test(line)) {
        findings.push(`${file}:${lineNumber}: canvas text APIs require an explicit typography standard review.`);
      }
    }
  }

  for (const file of sourceFiles([".svg"])) {
    for (const { line, lineNumber } of readLines(file)) {
      if (/<text\b|font-size\s*=|font-size\s*:/.test(line)) {
        findings.push(`${file}:${lineNumber}: SVG text must be reviewed against typography standards.`);
      }
    }
  }

  return findings;
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
console.log("- docs/typography-standards.md");
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
const typographyFindings = findTypographyFindings();
if (typographyFindings.length > 0) {
  console.error("PowerJack UX Design Standards Check failed.");
  console.error("Typography standards drift:");
  for (const finding of typographyFindings) {
    console.error(`- ${finding}`);
  }
  process.exitCode = 1;
  console.log("");
}

console.log("");
console.log("Agent pre-commit checklist:");
console.log("- Steel Focus palette and shared tokens are preserved.");
console.log("- Text uses the four shared typography tokens from docs/typography-standards.md.");
console.log("- Layout remains mobile-first, compact, and readable.");
console.log("- Workout logging stays dense: shared labels, horizontal set rows, no large card per set.");
console.log("- Selected, active, complete, disabled, locked, and error states are visible without relying on color alone.");
console.log("- Motion is short, causal, and does not delay logging.");
console.log("- Copy is short, calm, direct, and not gamified.");
console.log("- Controls keep accessible roles/names and stable data-agent-id selectors.");
console.log("- Browser/mobile visual QA and screenshot or E2E evidence are recorded when layout changes.");
console.log("- Any intentional standard deviation is explained in the handoff.");
