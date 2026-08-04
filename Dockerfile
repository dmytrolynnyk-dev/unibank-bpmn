# Custom Dockerfile for a Corezoid Git Call node — Lean isn't one of Git Call's
# natively supported languages (JS/Go/Python/Java/PHP/Clojure/Lisp/Prolog), so
# this image builds the Lean toolchain itself and exposes the compiled
# `asan_identity_gate` executable (Main.lean) as the entrypoint.
#
# STATUS / CAVEAT: written without ever building or running it. Two things in
# particular need confirming against a real Git Call setup before trusting
# this file:
#   1. Whether Git Call expects the container to run once per call (stdin in,
#      stdout out, exit) — assumed here — or stay warm as a long-lived process
#      handling repeated requests. If it's the latter, ENTRYPOINT needs to be
#      a small server loop instead of a one-shot binary.
#   2. The exact `lake build` output path for the executable — shown below as
#      `.lake/build/bin/asan_identity_gate`, which is current for recent Lake
#      versions, but varies across Lake releases.
#
# `lake update` pulls mathlib4 on image build — this is the real cost behind
# "Git Call is heavier than a Code node": expect a slow first build, not a
# fast cold start.

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \
      | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /app
COPY lean-toolchain lakefile.toml ./
COPY AsanIdentityGate.lean Main.lean ./

# lean-toolchain pins the exact Lean version elan installs; lake update
# resolves lakefile.toml's mathlib dependency and writes lake-manifest.json.
RUN lake update && lake build asan_identity_gate

ENTRYPOINT ["/app/.lake/build/bin/asan_identity_gate"]
