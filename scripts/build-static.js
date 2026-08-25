const fs = require("node:fs");
const path = require("node:path");

const rootDir = path.resolve(__dirname, "..");
const sourceDir = path.join(rootDir, "dashboard");
const outputDir = path.join(rootDir, "dist");
const excludedNames = new Set([".gitignore", "backend", "README.md"]);

function copyStaticFiles(source, target) {
  fs.mkdirSync(target, { recursive: true });

  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    if (excludedNames.has(entry.name)) {
      continue;
    }

    const sourcePath = path.join(source, entry.name);
    const targetPath = path.join(target, entry.name);

    if (entry.isDirectory()) {
      copyStaticFiles(sourcePath, targetPath);
    } else if (entry.isFile()) {
      fs.copyFileSync(sourcePath, targetPath);
    }
  }
}

fs.rmSync(outputDir, { recursive: true, force: true });
copyStaticFiles(sourceDir, outputDir);

console.log(`Built static dashboard into ${path.relative(rootDir, outputDir)}`);
