#!/usr/bin/env node
// The JavaScript entry (index.js) against the declarations (dist/index.d.ts): `npm test`, which
// prepublishOnly runs after the build, and preflight run it. Needs a build (dist/) first.
//
// This package has no run-time code. index.js declares, as undefined, every name that
// dist/index.d.ts exports, so that whatever loads the package at run time finds them: webpack's
// export check, Node's ES module loader, a bundler compiling one file at a time. Here: the two
// lists are equal (a type added to src/index.ts needs its name in index.js), nothing has a value,
// the __esModule marker is still there, and an ES module can import every name through "exports".
"use strict";
const path = require("path");
const { execFileSync } = require("child_process");
const ts = require("typescript");

const root = path.resolve(__dirname, "..");
const { name } = require(path.join(root, "package.json"));
const fail = (message) => {
  console.error(`check-entry: ${message}`);
  process.exit(1);
};

// The names the declarations export, as TypeScript resolves them.
const dts = path.join(root, "dist", "index.d.ts");
const program = ts.createProgram([dts], {});
const source = program.getSourceFile(dts) || fail("no dist/index.d.ts — run npm run build first");
const checker = program.getTypeChecker();
const declared = checker.getExportsOfModule(checker.getSymbolAtLocation(source)).map((s) => s.name).sort();

// require(): "main", every declared name and nothing else, none with a value.
const entry = require(root);
const runtime = Object.keys(entry).sort();
if (runtime.join() !== declared.join()) {
  fail(`index.js declares [${runtime.join(", ")}], dist/index.d.ts exports [${declared.join(", ")}]`);
}
const valued = runtime.filter((key) => entry[key] !== undefined);
if (valued.length) fail(`index.js gives ${valued.join(", ")} a value; this package has no run-time code`);
if (entry.__esModule !== true) fail("index.js lost its __esModule marker, which Rollup and Vite need");

// import: from an ES module, by package name (through "exports"), every name.
const named = declared.filter((key) => key !== "default").join(", ");
try {
  execFileSync(process.execPath, ["--input-type=module", "-e", `import D, { ${named} } from "${name}";`], {
    cwd: root,
    stdio: ["ignore", "inherit", "inherit"],
  });
} catch {
  fail(`an ES module cannot import { ${named} } and the default from ${name}`);
}

console.log(`check-entry: index.js declares ${declared.join(", ")}, all undefined; require() and import load it`);
