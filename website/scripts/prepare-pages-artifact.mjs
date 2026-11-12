import { cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const websiteDir = resolve(scriptDir, "..");
const rootDir = resolve(websiteDir, "..");

const outDir = join(websiteDir, "out");
const appcastSource = join(rootDir, "release", "appcast.xml");
const releaseNotesSourceDir = join(rootDir, "release", "release-notes");
const cnameSource = join(websiteDir, "CNAME");

function die(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function info(message) {
  console.log(`[prepare-pages] ${message}`);
}

if (!existsSync(outDir)) {
  die(`Missing Next export output directory: ${outDir} (did next build produce it?)`);
}
if (!existsSync(appcastSource)) {
  die(`Missing Sparkle appcast source: ${appcastSource}`);
}
if (!existsSync(releaseNotesSourceDir)) {
  die(`Missing release notes source directory: ${releaseNotesSourceDir}`);
}

if (existsSync(cnameSource)) {
  cpSync(cnameSource, join(outDir, "CNAME"));
  info("Copied CNAME");
}

writeFileSync(join(outDir, ".nojekyll"), "");

cpSync(appcastSource, join(outDir, "appcast.xml"));
info("Copied appcast.xml");

const releaseNotesOutDir = join(outDir, "release-notes");
rmSync(releaseNotesOutDir, { force: true, recursive: true });
mkdirSync(releaseNotesOutDir, { recursive: true });
cpSync(releaseNotesSourceDir, releaseNotesOutDir, { recursive: true });
info("Copied release notes");

info("Done");
