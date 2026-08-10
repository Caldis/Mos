// Single-package-manager guard — this project is npm-only.
//
// A second lockfile (pnpm-lock.yaml / yarn.lock / bun.lockb) means the dependency tree
// resolved on a dev's machine can drift from what CI installs (`npm ci`) and what ships.
// npm runs this on `preinstall`, before anything is fetched; pnpm/yarn/bun each announce
// themselves in npm_config_user_agent, so we can reject them with a clear message.
const ua = process.env.npm_config_user_agent || "";
const pm = ua.split("/")[0];
if (pm && pm !== "npm") {
  console.error(
    `\n  ✗ This project is npm-only — detected "${pm}".\n` +
      `    Use:  npm install   (and commit only package-lock.json)\n` +
      `    Why:  ${pm} writes its own lockfile and drifts from CI's \`npm ci\`.\n`,
  );
  process.exit(1);
}
