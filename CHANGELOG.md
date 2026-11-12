# CHANGELOG

## Unreleased
* Loading the package no longer throws `ReferenceError: BackgroundFetch is not defined`. 1.0.0's JavaScript entry exported the `BackgroundFetch` class, which only exists as a type declaration. That broke any build that loads the package at run time, such as esbuild, Vite, or Babel or SWC compiling TypeScript one file at a time, when the source had a plain `import { … }` or `export { … } from` of these types. The package now ships only its type declarations (`dist/*.d.ts`, unchanged) and a JavaScript entry (`index.js`) with no code: it declares each exported name as `undefined`, so webpack and Node's ES module loader also accept a plain named import of these types.

## 1.0.0 &mdash; 2026-04-13
* Initial release: the shared TypeScript types of the Background Fetch SDK (`BackgroundFetchConfig`, `TaskConfig`, `HeadlessEvent`, `BackgroundFetchStatus`, `NetworkType` and the `BackgroundFetch` API), used by `react-native-background-fetch`, `@transistorsoft/capacitor-background-fetch` and `cordova-plugin-background-fetch`.
