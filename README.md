# ASAN Identity Gate — Lean proof + Git Call skeleton

STATUS: the Lean proofs, the compiled binary's behavior, and the HTTP-bridge
mechanism have been verified locally (elan/lake toolchain install, `lake
build`, direct stdin/stdout calls, and calls through `server.py` over real
HTTP — see `Files` below for what changed as a result). **Not yet verified**:
building the actual `Dockerfile` inside a container (no Docker available in
the environment this was checked from) and Corezoid's real request/response
field names for a custom-Dockerfile Git Call node (see `What's still open`).
No Corezoid node exists yet.

## The question this answers

Across the CRM retail-lending journey, identity gets checked against ASAN
(Azerbaijan's government identity service) at two points:

- `fc_task_asan` — First Contact (`BPM/BPMN/02_First_Contact.bpmn`)
- `ver_task_asan2` — Verifier re-check (`BPM/BPMN/04_Verifer.bpmn`)

The question: **does the process actually require at least one of these two
checks to succeed before an applicant can reach final approval
(`ver_end_approve`)?** Formalizing that question in Lean — rather than just
eyeballing the two BPMN diagrams — is what this folder is about.

## The finding

No. As currently drawn:

- `fc_task_asan` expands into the `AsanVerification` subprocess
  (`05_ASAN_Verification.bpmn`). Every path through it — automated `Found`, or
  `Not Found`/`Timeout` routed to `asan_task_manual` (branch staff) — reaches
  `asan_end_ok`. There is no reject/failure end event anywhere in that
  subprocess, including no "staff couldn't verify either" outgoing flow from
  `asan_task_manual`.
- `ver_task_asan2` (`04_Verifer.bpmn`) has no gateway reading its result at
  all: `ver_sf2 -> ver_task_asan2 -> ver_sf3 -> ver_task_blacklist` is an
  unconditional sequence flow. Contrast with `ver_gw_docs`, `ver_gw_employ`,
  `ver_gw_final` elsewhere in the same diagram, which DO gate on their
  preceding task's outcome.

So nothing in the graph stops an applicant whose identity was never
successfully confirmed by either checkpoint from reaching approval on ASAN
grounds. `AsanIdentityGate.lean` states this precisely and proves it (Theorem
1), then proves that adding one gate — matching the pattern already used by
`ver_gw_docs`/`ver_gw_employ`/`ver_gw_final` — fixes it (Theorem 2).

This is deliberately scoped to just these two nodes. It says nothing about
blacklist/PEP checks, document verification, employment verification, or
FATCA — those already have their own explicit gateways and are out of scope.
It also does not decide whether a manual branch-staff override should count
as equivalent evidence to an automated ASAN match — that's a business
decision for whoever owns this control, not something this file resolves.

## Files

| File | Role |
|---|---|
| `AsanIdentityGate.lean` | The proof. Defines `CheckOutcome` (Verified/Unverified), models today's graph and a hypothetical fixed graph as `reachesApproval`, proves today's is unsafe (Theorem 1) and the fix is sufficient (Theorem 2). Also defines `reachesApprovalDecide` — a `Bool`-valued, actually-executable twin of `reachesApproval` (which is `Prop`-valued and has no runtime value) — and proves the two agree (Theorem 3). `reachesApprovalDecide` is the only thing here that could ever be *called*; the theorems are compile-time certificates, not runtime functions. **Rewritten to drop the mathlib4 dependency**: Theorem 1 no longer uses `push_neg` (replaced with `cases`/`exact` on the `Or` witness), Theorem 2 is `exact h` (holds by definitional unfolding), Theorem 3 uses core `simp` instead of `simpa`. All three compile and check under a plain Lean 4 toolchain — verified locally. |
| `Main.lean` | The Git Call entrypoint's JSON-RPC logic. Reads one JSON-RPC request from stdin, calls `reachesApprovalDecide`, writes a JSON-RPC reply to stdout — **verified locally**, including the malformed-input error path. The exact request/response field names are still a reasonable guess at standard JSON-RPC 2.0, **not confirmed** against Corezoid's actual Git Call payload shape. |
| `server.py` | HTTP bridge added because Git Call's actual contract for a custom Dockerfile is an HTTP server on `$GIT_CALL_PORT` handling JSON-RPC 2.0 POSTs — the original one-shot stdin/stdout `ENTRYPOINT` never satisfied that. Forwards each POST body to `asan_identity_gate` as a subprocess call and returns its stdout line as the response. **Verified locally** end-to-end over real HTTP. |
| `Dockerfile` | Builds a custom image: installs elan, runs `lake build` (no `lake update` needed — zero external requires now), then runs `server.py` as `ENTRYPOINT` instead of the binary directly. Needed because Lean is not one of Git Call's natively supported languages (JS/Go/Python/Java/PHP/Clojure/Lisp/Prolog). The toolchain/build steps were verified outside a container (same lean-toolchain version, same lakefile); **the literal `docker build` of this file has not been run** (no Docker available in the environment this was checked from). |
| `lakefile.toml` | Lake project manifest. **mathlib4 dependency dropped** — the proofs were rewritten to need only core Lean 4 tactics. Declares just the `asan_identity_gate` executable target; no `[[require]]` entries. |
| `lean-toolchain` | Pins the exact Lean 4 version elan should install — confirmed to install and build cleanly (elan 4.2.3, lean4 v4.11.0). |

## How this would connect to Corezoid (if built out)

1. This folder gets pushed to a git repository. That repo — not any Corezoid
   node — is the source of truth for the logic.
2. CI runs `lake build` on every push. If a theorem stops holding, the build
   fails and nothing gets published — this is the actual enforcement
   mechanism, not something checked per call.
3. A Corezoid **Git Call** node is configured to point at that repo (URL +
   branch/ref) using the custom-Dockerfile mode. The node's own configuration
   only holds this pointer plus field-mapping/timeout settings — none of the
   code above lives inside the node itself.
4. If the repo is private, Git Call's fixed outbound IPs
   (`54.171.15.37`, `108.128.68.222`, `63.33.226.230`) need whitelisting on
   the git host.
5. At runtime, the node calls the container's `handle(data)`, which runs
   `reachesApprovalDecide` — the proven-equivalent, compiled function — and
   returns its result as the task's reply.

## What's still open

- **Proportionality**: `reachesApprovalDecide`'s actual logic is a single
  boolean OR (`fc = Verified ∨ recheck = Verified`) — the same complexity
  class as a native Corezoid Condition node. Running it through Git Call
  (container build/warm-up, external git dependency, IP whitelisting) is
  heavy machinery for a one-line check. This proof's real payoff so far is at
  design time — it told us the gate is missing and exactly what condition to
  add — not necessarily as a live Git Call at runtime. Worth revisiting if
  the gate's logic grows past a simple OR.
- **Git Call's real contract for a custom-Dockerfile node** — the HTTP-on-
  `$GIT_CALL_PORT` requirement is confirmed from the plugin's Git Call docs,
  and `server.py` implements it, but the exact JSON-RPC request/response field
  names Corezoid actually sends have not been confirmed against a live task
  run. Compare against a working example (e.g. the AntiFraud/RTP track's
  existing Lean + Git Call setup, if one exists) before trusting `Main.lean`'s
  field names past "the mechanism works."
- **The literal `docker build` of `Dockerfile` has not been run** — the
  toolchain install and `lake build` were verified outside a container
  (matching Lean version, matching lakefile), but apt package availability
  and behavior specifically inside `ubuntu:22.04` were not exercised.
- **Business decision on manual override** — if `asan_task_manual`'s outcome
  should count differently from an automated match, `CheckOutcome` needs a
  third case and the proofs need revisiting.
