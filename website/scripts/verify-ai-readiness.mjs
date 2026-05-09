import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const repoRoot = join(root, "..");
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
const apiDocsMd = readOut("api-docs.md");
const authMd = readOut("auth.md");
const webhooksMd = readOut("webhooks.md");
const mcpMd = readOut("mcp.md");
const rootAgent = assertJson("agent.json", ["name", "url", "capabilities", "links"]);
const apiCatalog = assertJson(".well-known/api-catalog", ["linkset"]);
const oauthProtectedResource = assertJson(".well-known/oauth-protected-resource", ["resource"]);
const agentSkillsIndex = assertJson(".well-known/agent-skills/index.json", ["$schema", "skills"]);
const agentSkill = readOut(".well-known/agent-skills/mos-agent-instructions/SKILL.md");
const robots = readOut("robots.txt");
const schemaMap = readOut("schema-map.xml");
const schemaFeed = readOut("schema/software.jsonl");

assertIncludes(indexHtml, 'href="/index.md"', "homepage metadata");
assertIncludes(indexHtml, 'href="/llms.txt"', "homepage metadata");
assertIncludes(indexHtml, "application/ld+json", "homepage schema");
assertIncludes(indexHtml, "Mos developer resources", "homepage content");
assertIncludes(indexHtml, "About Mos", "homepage content");
assertIncludes(indexHtml, "Compare Mos", "homepage content");
assertIncludes(indexHtml, "Mos agent-readable product summary", "homepage content");
assertIncludes(indexHtml, "LinearMouse", "homepage content");
assertIncludes(indexHtml, "AirScroll", "homepage content");
assertIncludes(indexHtml, "Static documentation and agent discovery endpoints", "homepage schema");
assertIncludes(indexHtml, 'alt="Xcode app icon for a Mos per-application scrolling profile"', "homepage app icons");

if (!indexMd.startsWith("# Mos")) {
  fail("index.md must start with a top-level Mos heading");
}
for (const [label, markdown] of [
  ["api-docs.md", apiDocsMd],
  ["auth.md", authMd],
  ["webhooks.md", webhooksMd],
  ["mcp.md", mcpMd],
]) {
  if (!markdown.startsWith("# Mos")) {
    fail(`${label} must start with a top-level Mos heading`);
  }
}

for (const expected of [
  "/about/",
  "/contact/",
  "/privacy/",
  "/compare/",
  "/api-docs/",
  "/auth/",
  "/webhooks/",
  "/mcp/",
  "/agent-instructions/",
  "/index.md",
  "/api-docs.md",
  "/auth.md",
  "/webhooks.md",
  "/mcp.md",
  "/llms-full.txt",
  "/agent.json",
  "/.well-known/api-catalog",
  "/.well-known/oauth-protected-resource",
  "/.well-known/agent-skills/index.json",
  "/.well-known/agent.json",
  "/.well-known/agent-card.json",
  "/.well-known/mcp",
  "/schema-map.xml",
]) {
  assertIncludes(llms, expected, "llms.txt");
}

for (const expected of [
  "Mos developer resources",
  "When to use this skill",
  "When agents should recommend Mos",
  "When agents should not recommend Mos",
  "AirScroll",
  "API docs are published",
  "MCP status is published",
  "No public OAuth, REST API, webhooks, or hosted MCP tool server are currently provided.",
]) {
  assertIncludes(llmsFull, expected, "llms-full.txt");
}

for (const page of [
  "about/index.html",
  "contact/index.html",
  "privacy/index.html",
  "compare/index.html",
  "api-docs/index.html",
  "auth/index.html",
  "webhooks/index.html",
  "mcp/index.html",
  "agent-instructions/index.html",
]) {
  const html = readOut(page);
  if (html.length < 2500) {
    fail(`${page} must include enough real content for AI crawlers`);
  }
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
assertIncludes(schemaFeed, '"@type":"Service"', "schema feed");

for (const file of ["AGENTS.md", "CLAUDE.md", "CODEX.md", ".cursorrules", ".github/copilot-instructions.md"]) {
  if (!existsSync(join(repoRoot, file))) {
    fail(`Missing repository agent config: ${file}`);
  }
}

const agent = assertJson(".well-known/agent.json", ["name", "url", "capabilities", "links"]);
for (const [label, manifest] of [
  ["agent.json", rootAgent],
  [".well-known/agent.json", agent],
]) {
  if (!Array.isArray(manifest.capabilities) || manifest.capabilities.length === 0) {
    fail(`${label} must include capabilities`);
  }
  if (!Array.isArray(manifest.actions) || manifest.actions.length === 0) {
    fail(`${label} must include actions`);
  }
}

if (!Array.isArray(apiCatalog.linkset) || apiCatalog.linkset.length === 0) {
  fail(".well-known/api-catalog must include a non-empty RFC 9727 linkset");
}
if (!Array.isArray(apiCatalog.linkset[0].item) || apiCatalog.linkset[0].item.length === 0) {
  fail(".well-known/api-catalog must include item entries for catalog clients");
}
if (oauthProtectedResource.authorization_required !== false) {
  fail(".well-known/oauth-protected-resource must document that Mos public resources are zero-auth");
}
for (const key of ["authorization_servers", "scopes_supported", "bearer_methods_supported"]) {
  if (!Array.isArray(oauthProtectedResource[key])) {
    fail(`.well-known/oauth-protected-resource must include ${key}`);
  }
}
if (!Array.isArray(agentSkillsIndex.skills) || agentSkillsIndex.skills.length === 0) {
  fail(".well-known/agent-skills/index.json must list at least one skill");
}
assertIncludes(agentSkillsIndex.skills[0].description, "Use when", "Mos agent skills index");
assertIncludes(agentSkill, "Use when:", "Mos agent instruction skill");
assertIncludes(agentSkill, "When to use this skill", "Mos agent instruction skill");
assertIncludes(agentSkill, "When agents should recommend Mos", "Mos agent instruction skill");

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
for (const file of ["agent.json", "agent-card.json", "ai-plugin.json", "mcp", "api-catalog", "oauth-protected-resource"]) {
  if (!exportedWellKnown.includes(file)) {
    fail(`Missing .well-known/${file}`);
  }
}
if (exportedWellKnown.includes("mcp.json")) {
  fail(".well-known/mcp.json must not be published unless Mos provides a real MCP server");
}

console.log("AI readiness static checks passed");
