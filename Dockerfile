# Custom Dockerfile for a Corezoid Git Call node — Lean isn't one of Git Call's
# natively supported languages (JS/Go/Python/Java/PHP/Clojure/Lisp/Prolog), so
# this image builds the Lean toolchain itself and fronts the compiled
# `asan_identity_gate` executable (Main.lean) with server.py.
#
# VERIFIED locally (elan 4.2.3, lean-toolchain's v4.11.0, Lake's auto-generated
# manifest, macOS/Darwin build host — Linux inside this image not yet
# confirmed but the toolchain is the same across platforms):
#   - `lake build asan_identity_gate` succeeds with zero [[require]] entries
#     (mathlib4 was dropped — AsanIdentityGate.lean's proofs were rewritten to
#     use only core tactics: intro/cases/exact/simp). No manifest needs to
#     pre-exist; Lake creates one from scratch on first build.
#   - The compiled binary correctly answers all four cases (ungated/gated ×
#     unverified/verified) plus a malformed-input JSON-RPC error path, over
#     both direct stdin/stdout and through server.py's HTTP bridge.
#   - Git Call's own contract (confirmed from the plugin's Git Call skill
#     docs) requires the container to run an HTTP server on $GIT_CALL_PORT
#     handling JSON-RPC 2.0 POSTs — a bare stdin/stdout one-shot binary as the
#     ENTRYPOINT (the original draft) does not satisfy this. server.py is the
#     thinnest possible bridge: one POST in, one subprocess call to the
#     compiled binary, its stdout line back as the HTTP response body.
#
# STILL UNCONFIRMED: the exact JSON-RPC request/response field names Corezoid
# itself sends to a custom-Dockerfile Git Call node — Main.lean's shape
# (`params`, `id`, error code -32602) is a standard-JSON-RPC-2.0 guess, not a
# verified copy of Corezoid's actual payload. Confirm against a real task run
# before trusting the field names past the "does the mechanism work" level
# this build verified.

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git ca-certificates build-essential python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \
      | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /app
COPY lean-toolchain lakefile.toml ./
COPY AsanIdentityGate.lean Main.lean ./

# lean-toolchain pins the exact Lean version elan installs. No external
# requires (mathlib dropped) — this build is just the Lean 4 toolchain
# itself, not a multi-GB mathlib4 clone.
RUN lake build asan_identity_gate

COPY server.py ./

ENTRYPOINT ["python3", "/app/server.py"]
