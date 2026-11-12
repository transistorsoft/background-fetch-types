# Releasing

`@transistorsoft/background-fetch-types` is published by GitHub Actions
(`.github/workflows/release.yml`) when a version tag is pushed. npm trusts that workflow
through **Trusted Publishing** (OIDC), so no npm token exists anywhere, and every release
carries **provenance**: a signed record of the repository, commit and workflow that built it.
The React Native, Capacitor and Cordova background-fetch plugins release the same way, as do
the background-geolocation plugins.

## A release

```bash
npm run release -- prepare 1.0.2   # branch chore/release-1.0.2: version, dated CHANGELOG, preflight
# merge chore/release-1.0.2 into master
npm run release -- tag 1.0.2       # on master: tag the merge (lightweight and bare, like the plugins' tags)
git push origin master 1.0.2       # the tag starts the workflow
```

`prepare` releases the CHANGELOG's `## Unreleased` section, which must hold at least one
`* ` entry, as `## 1.0.2 &mdash; <today>`. It runs from an up-to-date master and refuses a
version that is not greater than package.json's, or is already on npm.

The workflow checks that the tag equals `package.json`'s version, then runs
`scripts/preflight.sh --release`:

- the build: declarations only, no JavaScript in `dist/`;
- the packed tarball's contents, and what changed since the version on npm, declarations included;
- a strict consumer compile;
- the module loading at runtime;
- a CHANGELOG heading for the version.

If those pass, it publishes. A prerelease such as `1.1.0-beta.1` is published under the `beta`
dist-tag, so `latest` only moves to a release.

This package is **TypeScript declarations only**. `tsc` emits only `dist/*.d.ts`
(`emitDeclarationOnly`), which is gitignored and built at publish (`prepublishOnly`). The
JavaScript entry that `main` and `exports` name is the committed, empty `index.js`. It exists
so that a bundler compiling one file at a time (esbuild, Vite, Babel or SWC with TypeScript)
loads nothing, instead of failing on a plain `import { … }` or `export { … } from` of these
types. 1.0.0 shipped `tsc`'s JavaScript for `src/BackgroundFetch.ts`, which threw
`ReferenceError: BackgroundFetch is not defined` on load, because that class exists only as a
declaration. Never give the package run-time code. The `test` script (`require()` of the
package) and preflight refuse a build that throws on load or puts JavaScript in `dist/`.

What ships is decided by `"files"` in `package.json`: `dist/` and `index.js`, plus what npm
always adds. Preflight refuses anything else. The build uses the repository's own TypeScript
(a devDependency, through `npm ci`), so the output does not depend on whatever `tsc` a machine
has installed. 1.0.0 was built by a global `tsc` 4.1, so its `dist/types.d.ts` reads
`export declare type` where 5.x writes `export type`. The two mean the same.

`npm run preflight` (without `-- --release`) is safe to run at any time; it publishes nothing.
Never add a `version`, `preversion` or `postversion` script: `release -- prepare` runs
`npm version`, which would run them.

After a release, the plugins pick it up through their `^1.0.0` range, but Capacitor and
Cordova commit a `package-lock.json`. Run `npm update @transistorsoft/background-fetch-types`
there and commit the lockfile.

## A release that failed

Fix the cause, then re-run from the Actions tab: **release → Run workflow → Use workflow
from → Tags → the version**. The workflow refuses to run on a branch, and skips the publish
if that version is already on npm. A version can be published once, ever: if a bad tag was
pushed, delete it and release the next patch version rather than re-using the number.

## Checking a release

- The package page on npmjs.com shows a provenance badge linking to the workflow run. npm
  shows the new version as "validating" for a few minutes before it serves it.
- `npm audit signatures`, in a project that depends on the package, verifies it.

## One-time setup

On npmjs.com, the package's **Settings → Trusted Publisher → GitHub Actions**:
organization `transistorsoft`, repository `background-fetch-types`, workflow `release.yml`,
environment blank. GitHub Environments are not available on this org's plan, and the
registration and the workflow must agree. **Publishing access**: "Require two-factor
authentication and disallow bypass 2fa tokens". GitHub needs nothing: no secrets, no
environment.
