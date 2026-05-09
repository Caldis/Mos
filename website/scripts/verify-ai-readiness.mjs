import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const outDir = join(root, "out");

function fail(message) {
  throw new Error(message);
}

function readOut(relativePath) {
  const path = join(outDir, relativePath);
  if (!existsSync(path)) {
    fail(`Missing exported file: ${relativePath}`);
  }
  return readFileSync(path, "utf8");
}

function assertIncludes(haystack, needle, label) {
  if (!haystack.includes(needle)) {
    fail(`${label} must include ${needle}`);
  }
}

function assertJson(relativePath, requiredKeys = []) {
  const raw = readOut(relativePath);
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
  }

  for (const key of requiredKeys) {
    if (!(key in parsed)) {
      fail(`${relativePath} must include "${key}"`);
    }
  }

  return parsed;
}

const indexHtml = readOut("index.html");
const indexMd = readOut("index.md");
const llms = readOut("llms.txt");
const llmsFull = readOut("llms-full.txt");
const robots = readOut("robots.txt");
const schemaMap = readOut("schema-map.xml");
const schemaFeed = readOut("schema/software.jsonl");

assertIncludes(indexHtml, 'href="/index.md"', "homepage metadata");
assertIncludes(indexHtml, 'href="/llms.txt"', "homepage metadata");
assertIncludes(indexHtml, "application/ld+json", "homepage schema");
assertIncludes(indexHtml, "Mos developer resources", "homepage content");
assertIncludes(indexHtml, 'alt="Xcode app icon for a Mos per-application scrolling profile"', "homepage app icons");

if (!indexMd.startsWith("# Mos")) {
  fail("index.md must start with a top-level Mos heading");
}

for (const expected of [
  "/index.md",
  "/llms-full.txt",
  "/.well-known/agent.json",
  "/.well-known/agent-card.json",
  "/.well-known/mcp",
  "/schema-map.xml",
]) {
  assertIncludes(llms, expected, "llms.txt");
}

for (const expected of [
  "Mos developer resources",
  "No public OAuth, REST API, webhooks, or hosted MCP tool server are currently provided.",
]) {
  assertIncludes(llmsFull, expected, "llms-full.txt");
}

for (const expected of [
  "Content-Signal: search=yes, ai-input=yes, ai-train=no",
  "User-agent: CCBot",
  "User-agent: ByteSpider",
  "Schemamap: https://mos.caldis.me/schema-map.xml",
]) {
  assertIncludes(robots, expected, "robots.txt");
}

assertIncludes(schemaMap, "https://mos.caldis.me/schema/software.jsonl", "schema map");
assertIncludes(schemaFeed, '"@type":"SoftwareApplication"', "schema feed");

const agent = assertJson(".well-known/agent.json", ["name", "url", "capabilities", "links"]);
if (!Array.isArray(agent.capabilities) || agent.capabilities.length === 0) {
  fail(".well-known/agent.json must include capabilities");
}

const agentCard = assertJson(".well-known/agent-card.json", [
  "name",
  "description",
  "url",
  "version",
  "skills",
]);
if (!Array.isArray(agentCard.skills) || agentCard.skills.length === 0) {
  fail(".well-known/agent-card.json must include skills");
}

const mcp = assertJson(".well-known/mcp", ["name", "status", "documentation_url"]);
if (mcp.status !== "not_provided") {
  fail(".well-known/mcp must not claim a hosted MCP server unless one exists");
}

const exportedWellKnown = readdirSync(join(outDir, ".well-known"));
for (const file of ["agent.json", "agent-card.json", "ai-plugin.json", "mcp"]) {
  if (!exportedWellKnown.includes(file)) {
    fail(`Missing .well-known/${file}`);
  }
}

console.log("AI readiness static checks passed");
