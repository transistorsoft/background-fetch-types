// @transistorsoft/background-fetch-types ships TypeScript declarations only (dist/*.d.ts):
// it has no run-time code. This module is the package's JS entry, so that whatever loads the
// package at run time finds every name dist/index.d.ts exports, each undefined, instead of
// failing. That covers a bundler that compiles one file at a time (esbuild, Vite, Babel or
// SWC with TypeScript) and keeps a value-form `import`/`export {…} from` of these types,
// webpack's export check, and Node's own ES module loader. The __esModule marker is what
// Rollup and Vite need. scripts/check-entry.js (npm test) keeps this list equal to the
// declarations.
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = exports.BackgroundFetchConfig = exports.TaskConfig = exports.HeadlessEvent = exports.BackgroundFetchStatus = exports.NetworkType = void 0;
