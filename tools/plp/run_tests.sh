#!/usr/bin/env bash
# Run Precise Ledger Pro's own test suites in throwaway containers (ADR-0024).
#
#   bash tools/plp/run_tests.sh java|haskell SOURCE_DIR OUT_DIR
#
# The source is mounted read-only and copied inside the container, so their
# code never writes to the host. Two phases per language:
#   1. fetch dependencies, WITH network, into a named cache volume (no tests run);
#   2. build and test, with --network none, so the code under test can reach
#      nothing, including any address in its configuration.
# Images are pinned by digest below; the output dir receives the reports and logs.
set -euo pipefail

LANG_="$1"; SRC="$2"; OUT="$3"
mkdir -p "$OUT"

JAVA_IMAGE="maven:3.9.9-eclipse-temurin-21@sha256:${JAVA_DIGEST:?set JAVA_DIGEST}"
HASKELL_IMAGE="haskell:9.6.6@sha256:${HASKELL_DIGEST:?set HASKELL_DIGEST}"
# Quinoa would build the Vue web UI with Node from the network; the UI isn't
# under test, so it is switched off.
MVN_FLAGS="-B -Dquarkus.quinoa.enabled=false -Dstyle.color=never"

case "$LANG_" in
  java)
    docker run --rm -v "$SRC":/src:ro -v plp-m2:/root/.m2 "$JAVA_IMAGE" bash -c \
      "cp -r /src /work && cd /work && mvn $MVN_FLAGS -q dependency:go-offline dependency:resolve-plugins && mvn $MVN_FLAGS -DskipTests test && mvn $MVN_FLAGS -q dependency:get -Dartifact=org.apache.maven.surefire:surefire-junit-platform:3.2.5" \
      >"$OUT/java-fetch.log" 2>&1
    set +e
    docker run --rm --network none -v "$SRC":/src:ro -v plp-m2:/root/.m2 -v "$OUT":/out "$JAVA_IMAGE" bash -c \
      "cp -r /src /work && cd /work && mvn $MVN_FLAGS -o test; rc=\$?; mkdir -p /out/surefire-reports; cp target/surefire-reports/* /out/surefire-reports/ 2>/dev/null; exit \$rc" \
      >"$OUT/java-test.log" 2>&1
    echo "java exit $?" | tee "$OUT/java-exit.txt"
    ;;
  haskell)
    docker run --rm -v "$SRC":/src:ro -v plp-cabal:/root/.cabal -v plp-cabal-state:/root/.local/state/cabal "$HASKELL_IMAGE" bash -c \
      "cp -r /src/haskell /work && cd /work && cabal update && cabal build --only-dependencies --enable-tests" \
      >"$OUT/haskell-fetch.log" 2>&1
    set +e
    docker run --rm --network none -v "$SRC":/src:ro -v plp-cabal:/root/.cabal -v plp-cabal-state:/root/.local/state/cabal "$HASKELL_IMAGE" bash -c \
      "cp -r /src/haskell /work && cd /work && cabal test --enable-tests --test-show-details=direct" \
      >"$OUT/haskell-test.log" 2>&1
    echo "haskell exit $?" | tee "$OUT/haskell-exit.txt"
    ;;
  *) echo "usage: run_tests.sh java|haskell SOURCE_DIR OUT_DIR" >&2; exit 2 ;;
esac
