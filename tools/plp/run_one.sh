#!/usr/bin/env bash
# Run one of Precise Ledger Pro's suites (or one Java test) offline, on a source copy.
#   bash tools/plp/run_one.sh java|haskell SOURCE_DIR [JAVA_TEST]
set -uo pipefail
LANG_="$1"; SRC="$2"; TEST="${3:-}"
JAVA_IMAGE="maven:3.9.9-eclipse-temurin-21@sha256:3a4ab3276a087bf276f79cae96b1af04f53731bec53fb2e651aca79e4b10211e"
HASKELL_IMAGE="haskell:9.6.6@sha256:33e280e96a347f31cb9eb595c9e2ff134fc42d5175a50a9d958194d711402876"
if [ "$LANG_" = java ]; then
  docker run --rm --network none -v "$SRC":/src:ro -v plp-m2:/root/.m2 "$JAVA_IMAGE" bash -c \
    "cp -r /src /work && cd /work && mvn -B -o -Dquarkus.quinoa.enabled=false -Dstyle.color=never ${TEST:+-Dtest=$TEST} test"
else
  docker run --rm --network none -v "$SRC":/src:ro -v plp-cabal:/root/.cabal -v plp-cabal-state:/root/.local/state/cabal "$HASKELL_IMAGE" bash -c \
    "cp -r /src/haskell /work && cd /work && cabal test --enable-tests --test-show-details=direct"
fi
