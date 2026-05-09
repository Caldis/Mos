import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const appDir = join(root, "app");
const allowedHook = join(appDir, "hooks", "useHydratedReducedMotion.ts");

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) return walk(fullPath);
    return fullPath;
  });
}

function fail(message) {
  throw new Error(message);
}

if (!existsSync(allowedHook)) {
  fail("Missing app/hooks/useHydratedReducedMotion.ts");
}

const hookSource = readFileSync(allowedHook, "utf8");
if (!hookSource.includes("useReducedMotion")) {
  fail("useHydratedReducedMotion must wrap framer-motion useReducedMotion");
}

const offenders = walk(appDir)
  .filter((file) => /\.(tsx|ts)$/.test(file))
  .filter((file) => file !== allowedHook)
  .filter((file) => {
    const source = readFileSync(file, "utf8");
    return source.includes("useReducedMotion");
  });

if (offenders.length > 0) {
  fail(
    [
      "SSR-rendered components must not branch directly on useReducedMotion.",
      "Use app/hooks/useHydratedReducedMotion.ts so server and first client render match.",
      ...offenders.map((file) => `- ${file}`),
    ].join("\n")
  );
}

const hydrationSensitiveBranches = walk(appDir)
  .filter((file) => /\.(tsx|ts)$/.test(file))
  .filter((file) => {
    const source = readFileSync(file, "utf8");
    return (
      /initial=\{\s*shouldReduceMotion/.test(source) ||
      /style=\{\s*shouldReduceMotion/.test(source) ||
      /strokeDashoffset=\{\s*shouldReduceMotion/.test(source)
    );
  });

if (hydrationSensitiveBranches.length > 0) {
  fail(
    [
      "Reduced-motion state must not control SSR-sensitive motion attributes.",
      "Keep initial, style, and SVG stroke attributes deterministic for the server and first client render.",
      ...hydrationSensitiveBranches.map((file) => `- ${file}`),
    ].join("\n")
  );
}

console.log("Motion hydration checks passed");
