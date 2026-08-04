# ASAN Identity Gate — Lean proof + Git Call skeleton

STATUS: draft, unverified. Nothing in this folder has been run through a real
Lean/Lake toolchain, Docker, or Corezoid. No git repo, no pushed image, no
Corezoid node exists yet. This documents what's here and what it would take
to make it real.

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
| `AsanIdentityGate.lean` | The proof. Defines `CheckOutcome` (Verified/Unverified), models today's graph and a hypothetical fixed graph as `reachesApproval`, proves today's is unsafe (Theorem 1) and the fix is sufficient (Theorem 2). Also defines `reachesApprovalDecide` — a `Bool`-valued, actually-executable twin of `reachesApproval` (which is `Prop`-valued and has no runtime value) — and proves the two agree (Theorem 3). `reachesApprovalDecide` is the only thing here that could ever be *called*; the theorems are compile-time certificates, not runtime functions. |
| `Main.lean` | The would-be Git Call entrypoint. Reads one JSON-RPC request from stdin, calls `reachesApprovalDecide`, writes a JSON-RPC reply to stdout. The exact request/response field names are a reasonable guess at standard JSON-RPC 2.0, **not confirmed** against Corezoid's actual Git Call contract. |
| `Dockerfile` | Builds a custom image: installs elan (Lean's toolchain manager), runs `lake update && lake build`, sets the compiled `asan_identity_gate` binary as `ENTRYPOINT`. Needed because Lean is not one of Git Call's natively supported languages (JS/Go/Python/Java/PHP/Clojure/Lisp/Prolog). |
| `lakefile.toml` | Lake project manifest. Declares the mathlib4 dependency (needed only for the `push_neg` tactic in Theorem 1 — could be dropped if that proof were rewritten without it) and the `asan_identity_gate` executable target. |
| `lean-toolchain` | Pins the exact Lean 4 version elan should install. |

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
- **Git Call's real contract** — `Main.lean`'s request/response shape and
  whether the container runs once per call or stays warm need confirming
  against a working example, ideally the AntiFraud/RTP track's existing Lean
  + Git Call setup.
- **`lake update`/`lake build` have never been run** — no `lake-manifest.json`
  exists yet, and the mathlib4 dependency, Lean version, and Lake build
  output path (`.lake/build/bin/asan_identity_gate` in `Dockerfile`) are all
  best-effort guesses pending an actual toolchain run.
- **Business decision on manual override** — if `asan_task_manual`'s outcome
  should count differently from an automated match, `CheckOutcome` needs a
  third case and the proofs need revisiting.
