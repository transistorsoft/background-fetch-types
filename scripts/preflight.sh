#!/usr/bin/env bash
# Everything worth checking before a release — run by scripts/release.sh and by the
# release workflow, and safe to run any time.
#
#   scripts/preflight.sh             build, pack, then type-check and load a consumer against the tarball
#   scripts/preflight.sh --release   also: CHANGELOG has a heading for this version
#
# This package is TypeScript declarations and nothing else. tsc emits only dist/*.d.ts
# (emitDeclarationOnly), and the JavaScript entry is the committed, empty index.js. 1.0.0
# shipped tsc's JavaScript for src/BackgroundFetch.ts, whose `exports.default = BackgroundFetch`
# names a class that exists only as a declaration, so loading the package threw. dist/ is
# gitignored and rebuilt here. Publishes nothing; it reads the registry only to compare
# with the version on npm.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RELEASE=0
[ "${1:-}" = "--release" ] && RELEASE=1

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
ok()   { echo "  ${GREEN}✓${RESET} $1"; }
fail() { echo "  ${RED}✗${RESET} $1" >&2; exit 1; }
step() { echo; echo "${DIM}── $1${RESET}"; }

cd "$ROOT"
NAME="$(node -p "require('./package.json').name")"
VERSION="$(node -p "require('./package.json').version")"

step "1. version"
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || fail "package.json version '$VERSION' is not semver"
if [ "$RELEASE" = 1 ]; then
  # The first `## ` heading must be this version: an `## Unreleased` above it means the
  # notes were never given a version.
  first="$(grep -m1 '^## ' CHANGELOG.md || true)"
  case "$first" in
    "## $VERSION "*|"## [$VERSION] "*) ok "$NAME@$VERSION — CHANGELOG: $first" ;;
    *) fail "CHANGELOG's first heading is '$first', not '## $VERSION …' — run npm run release -- prepare" ;;
  esac
else
  ok "$NAME@$VERSION"
fi

step "2. build"
# The repository's own TypeScript (a devDependency, through npm ci), not whatever tsc a
# machine has installed: 1.0.0 was built by a global tsc 4.1.
[ -x node_modules/.bin/tsc ] || fail "no node_modules/.bin/tsc — run npm ci first"
npm run -s build >"$WORK/build.log" 2>&1 || { cat "$WORK/build.log" >&2; fail "npm run build"; }
js="$(find dist -name '*.js' | head -3 | tr '\n' ' ')"
[ -z "$js" ] || fail "dist/ has JavaScript ($js) — this package ships declarations only (tsconfig.json emitDeclarationOnly)"
ok "dist/ rebuilt by tsc $(node_modules/.bin/tsc --version | cut -d' ' -f2): $(find dist -name '*.d.ts' | wc -l | tr -d ' ') declaration files, no JavaScript"

step "3. the tarball"
# Its own directory: the version on npm, packed below, has the same file name whenever
# package.json still says the released version, and would overwrite this one.
mkdir -p "$WORK/pack" "$WORK/npm"
npm pack --silent --pack-destination "$WORK/pack" >/dev/null || fail "npm pack"
TARBALL="$(ls "$WORK"/pack/*.tgz)"
tar -tzf "$TARBALL" | sort > "$WORK/contents"
# The declarations index.d.ts reaches, and the empty JavaScript entry that "main" and
# exports["."].default name.
for want in package/package.json package/index.js package/dist/index.d.ts package/dist/BackgroundFetch.d.ts \
            package/dist/interfaces.d.ts package/dist/types.d.ts; do
  grep -qx "$want" "$WORK/contents" || fail "the tarball has no $want"
done
# "files" in package.json decides what ships: nothing beyond those, their maps, and what npm
# always adds.
bad="$(grep -Ev '^package/(package\.json|index\.js|dist/[A-Za-z]+\.d\.ts(\.map)?|README(\.md)?|LICEN[CS]E(\.md)?)$' "$WORK/contents" || true)"
[ -z "$bad" ] || fail "the tarball carries what it should not (\"files\" in package.json): $(echo "$bad" | head -3 | tr '\n' ' ')"
ok "$(basename "$TARBALL") — $(wc -l < "$WORK/contents" | tr -d ' ') files"
# Against the version on npm now: files that vanish or appear, and declarations whose text
# changed, are worth a look before they ship. Printed, not enforced — a deliberate change is fine.
PREV="$(npm view "$NAME" dist-tags.latest 2>/dev/null || true)"
if [ -n "$PREV" ] && (cd "$WORK/npm" && npm pack --silent "$NAME@$PREV" >/dev/null 2>&1); then
  PREV_TARBALL="$(ls "$WORK"/npm/*.tgz)"
  tar -tzf "$PREV_TARBALL" | sort > "$WORK/previous"
  gone="$(comm -23 "$WORK/previous" "$WORK/contents" | sed 's#^package/##')"
  new="$(comm -13 "$WORK/previous" "$WORK/contents" | sed 's#^package/##')"
  ok "against $PREV on npm: $(echo -n "$gone" | grep -c . || true) gone, $(echo -n "$new" | grep -c . || true) new"
  [ -z "$gone" ] || echo "$gone" | head -10 | sed 's/^/      - /'
  [ -z "$new" ] || echo "$new" | head -10 | sed 's/^/      + /'
  mkdir -p "$WORK/prev" "$WORK/this"
  tar -xzf "$PREV_TARBALL" -C "$WORK/prev"
  tar -xzf "$TARBALL" -C "$WORK/this"
  changed=""
  for d in "$WORK"/this/package/dist/*.d.ts; do
    f="$(basename "$d")"
    if [ -f "$WORK/prev/package/dist/$f" ] && ! cmp -s "$WORK/prev/package/dist/$f" "$d"; then
      changed="$changed $f"
    fi
  done
  if [ -z "$changed" ]; then
    ok "declarations: identical to $PREV"
  else
    ok "declarations changed since $PREV:$changed"
    for f in $changed; do
      { diff "$WORK/prev/package/dist/$f" "$WORK/this/package/dist/$f" || true; } \
        | grep '^[<>]' | head -6 | sed "s#^#      $f #" || true
    done
  fi
else
  echo "  ${DIM}(no published version to compare with)${RESET}"
fi

step "4. a consumer type-checks and loads it"
# How the plugins' users see these types: the default export is the BackgroundFetch API, a
# value (react-native-background-fetch re-exports it as its own default), with the five type
# names beside it. The consumer brings its own TypeScript.
mkdir -p "$WORK/consumer" && cd "$WORK/consumer"
echo '{"name": "consumer", "private": true}' > package.json
npm install --silent --no-audit --no-fund "$TARBALL" "typescript@^5" >/dev/null || fail "npm install of the tarball"
cat > index.ts <<'TS'
import BackgroundFetch from "@transistorsoft/background-fetch-types";
import type {
  BackgroundFetchConfig, BackgroundFetchStatus, HeadlessEvent, NetworkType, TaskConfig,
} from "@transistorsoft/background-fetch-types";

const config: BackgroundFetchConfig = {
  minimumFetchInterval: 15,
  stopOnTerminate: false,
  enableHeadless: true,
  requiredNetworkType: BackgroundFetch.NETWORK_TYPE_ANY,
};
export async function start(): Promise<boolean> {
  const status: BackgroundFetchStatus = await BackgroundFetch.configure(
    config,
    (taskId: string) => BackgroundFetch.finish(taskId),
    (taskId: string) => BackgroundFetch.finish(taskId),
  );
  const network: NetworkType = BackgroundFetch.NETWORK_TYPE_UNMETERED;
  const task: TaskConfig = { taskId: "com.transistorsoft.task", delay: 5000, periodic: false, requiredNetworkType: network };
  await BackgroundFetch.scheduleTask(task);
  BackgroundFetch.registerHeadlessTask(async (event: HeadlessEvent) => BackgroundFetch.finish(event.taskId));
  return status === BackgroundFetch.STATUS_AVAILABLE && (await BackgroundFetch.stop(task.taskId));
}
TS
# node10 is how a project with "moduleResolution": "node" finds them (the "types" field);
# node16 and bundler go through exports["."].types.
for mode in "commonjs node10" "node16 node16" "esnext bundler"; do
  set -- $mode
  ./node_modules/.bin/tsc --strict --noEmit --skipLibCheck false --target es2020 --lib es2020,dom \
    --module "$1" --moduleResolution "$2" index.ts \
    || fail "a strict consumer does not compile under moduleResolution $2"
done
ok "strict TypeScript compiles under node10, node16 and bundler resolution"
# A bundler that compiles one file at a time keeps a plain `import { … }` / `export { … } from`
# of these types and loads the module; 1.0.0 threw there. It must load, and export nothing.
node -e '
  const m = require("@transistorsoft/background-fetch-types");
  if (Object.keys(m).length || m.__esModule !== true) {
    console.error("require() exports", JSON.stringify(Object.keys(m)), "__esModule", m.__esModule); process.exit(1);
  }' || fail "require() of the package throws, or exports something"
node --input-type=module -e 'import m from "@transistorsoft/background-fetch-types"; await import("@transistorsoft/background-fetch-types");' \
  || fail "import of the package from an ES module throws"
ok "require() and import load an empty module"

echo
echo "${GREEN}preflight passed${RESET} — $NAME@$VERSION"
