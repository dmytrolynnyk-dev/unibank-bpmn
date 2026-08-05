/-
  ASAN identity-check gating — does reaching final approval actually require
  a confirmed identity?

  Scope: exactly two nodes, nothing else in the CRM journey.
    - `fc_task_asan`   (BPM/BPMN/02_First_Contact.bpmn)
      expands into the `AsanVerification` subprocess (05_ASAN_Verification.bpmn):
        asan_gw_response --Found--------------------> asan_task_store
                         --Not Found--> asan_task_manual --(unconditional)--> asan_task_store
                         --Timeout---> asan_task_manual --(unconditional)--> asan_task_store
      Every branch reaches asan_task_store, then asan_task_fatca, then asan_end_ok.
      There is NO reject/failure end event anywhere in this subprocess — including
      no outgoing flow from `asan_task_manual` for "staff couldn't verify either."
    - `ver_task_asan2` (BPM/BPMN/04_Verifer.bpmn)
      `ver_sf2 -> ver_task_asan2 -> ver_sf3 -> ver_task_blacklist`, unconditional.
      There is no gateway reading this task's result at all (no `ver_gw_asan2`) —
      contrast with `ver_gw_docs`, `ver_gw_employ`, `ver_gw_final`, which DO gate
      on their preceding task's outcome.

  Purpose: formalize the property the process almost certainly *intends* —
  "you cannot reach `ver_end_approve` unless at least one of the two ASAN
  checkpoints affirmatively confirmed identity" — and check whether the graph
  as currently drawn actually guarantees it, or only looks like it does.

  Result (spoiler, see theorems below): it does NOT. This file's value is in
  the act of stating the property precisely enough to prove, not in confirming
  something already known to be safe — unlike a threshold gateway, nobody can
  eyeball two BPMN files and be sure an outcome is never silently dropped on
  the floor across an unconditional sequence flow.

  STATUS: drafted by an LLM, not yet compiled against a real Lean toolchain.
  Treat as a spec-and-argument sketch for review, not a checked proof — hand
  to whoever owns the AntiFraud Lean tooling to load and fix any mismatches.
-/

/-- Whether a single ASAN checkpoint affirmatively confirmed identity.
    Deliberately binary for this first pass — see closing note on why
    `asan_task_manual` should probably become a third case later. -/
inductive CheckOutcome
  | Verified
  | Unverified
  deriving DecidableEq, Repr

/-- `reachesApproval fc recheck` models whether the journey, given these two
    checkpoint outcomes, can reach `ver_end_approve` — AS THE BPMN IS ACTUALLY
    DRAWN TODAY. `gated` toggles between that reality and a hypothetical fix.

    `gated = false` — today's graph: neither `fc_task_asan`'s subprocess nor
    `ver_task_asan2` has any outgoing flow that depends on `CheckOutcome`, so
    approval-reachability literally does not mention `fc`/`recheck` — it's a
    constant `True`, independent of whether identity was ever confirmed.

    `gated = true` — the graph WITH a hypothetical join-gate added (e.g. a new
    `ver_gw_asan2`-style condition before `ver_task_final_decision`, or
    equivalently right before `ver_end_approve`) that requires at least one
    checkpoint to have returned `Verified`. -/
def reachesApproval (gated : Bool) (fc recheck : CheckOutcome) : Prop :=
  if gated then fc = .Verified ∨ recheck = .Verified else True

/-- The safety property we actually want: reaching approval implies at least
    one checkpoint confirmed identity. -/
def safeGate (gated : Bool) : Prop :=
  ∀ fc recheck, reachesApproval gated fc recheck → (fc = .Verified ∨ recheck = .Verified)

/-- THEOREM 1 — the current graph does NOT satisfy the safety property.
    Witness: both checkpoints return `Unverified` — e.g. `fc_task_asan`'s
    subprocess took the Not-Found/Timeout → manual-check path and the manual
    check silently failed (no such outcome is even representable in the BPMN,
    which is itself part of the problem), AND `ver_task_asan2`'s re-check
    also failed. `reachesApproval false _ _` is `True` regardless, so nothing
    stops this pair from reaching `ver_end_approve`. -/
theorem current_graph_unsafe : ¬ safeGate false := by
  intro h
  cases h .Unverified .Unverified trivial with
  | inl heq => cases heq
  | inr heq => cases heq

/-- THEOREM 2 — a graph with the missing gate added IS safe, and trivially so.
    This is the constructive half: it shows the fix is not exotic tooling,
    it's exactly the kind of condition `ver_gw_docs`/`ver_gw_employ`/`ver_gw_final`
    already use elsewhere in the same diagram — a gateway checking `fc` and
    `recheck` before letting the token through. Once that gate exists, the
    safety property holds by construction, no separate proof effort needed. -/
theorem gated_graph_safe : safeGate true := by
  intro fc recheck h
  exact h

/-- `reachesApproval` returns `Prop` — it has no runtime value, so nothing can
    call it from outside Lean (a Git Call node included). This is the
    computable twin that actually gets compiled and invoked at runtime: same
    decision, `Bool`-valued instead of `Prop`-valued. This is what a
    `handle(data)` wrapper in the Git Call container would call, not the
    theorems above and not `reachesApproval` itself. -/
def reachesApprovalDecide (gated : Bool) (fc recheck : CheckOutcome) : Bool :=
  if gated then (fc == .Verified || recheck == .Verified) else true

/-- THEOREM 3 — the callable function agrees with the verified spec.
    Without this, `reachesApprovalDecide` would just be an independent,
    hand-written `Bool` function sitting next to the proof — no different
    from reimplementing the logic in JS and hoping it matches. This theorem
    is what lets the compiled binary inherit Theorem 1/2's guarantees: since
    `reachesApprovalDecide` is *proven* equal in meaning to `reachesApproval`,
    whatever the Git Call node returns at runtime is exactly what the proofs
    above are about — not a separate, unverified stand-in for it. -/
theorem reachesApprovalDecide_iff (gated : Bool) (fc recheck : CheckOutcome) :
    reachesApprovalDecide gated fc recheck = true ↔ reachesApproval gated fc recheck := by
  cases gated <;> cases fc <;> cases recheck <;>
    simp [reachesApprovalDecide, reachesApproval]

/-
  WHAT THIS FILE DELIBERATELY DOES NOT DO:

  - It does NOT model `ver_gw_docs`, `ver_gw_employ`, `ver_gw_final`, blacklist,
    or FATCA — those already have explicit gateways reading their preceding
    task's result; they are not the gap this file is about.
  - It does NOT decide whether `asan_task_manual` (branch-staff manual check)
    should count as equally strong evidence as the automated ASAN response.
    `CheckOutcome` is kept binary here (Verified/Unverified) precisely to dodge
    that judgment call — a real fix will likely need a third case
    (`ManualOverride`) plus a business decision on whether it satisfies the
    gate alone or needs a second signal. That decision belongs to whoever owns
    this control, not to this file.
  - It does NOT claim `fc_task_asan`'s subprocess or `ver_task_asan2` are
    "wrong" in some absolute sense — only that, as drawn, nothing in the graph
    prevents an unverified applicant from reaching approval on ASAN grounds
    alone. Other controls later in the journey (blacklist, doc-verify,
    employment) are unaffected and still apply independently.

  NEXT STEP if this is confirmed as a real gap: add the missing gate (either
  a new `ver_gw_asan2` right after `ver_task_asan2`, or one combined check
  reading both checkpoints' stored results just before `ver_gw_final`) to the
  actual BPMN/Corezoid implementation, then this file's Theorem 2 already
  covers it — nothing here needs to change.

  - It does NOT yet include a `main`/IO entrypoint (stdin/stdout or an actual
    JSON-RPC `handle(data)` implementation) — `reachesApprovalDecide` is the
    function such an entrypoint would call. See `Main.lean` for that piece.
-/
