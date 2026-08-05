# Corezoid Git Call entrypoint (lang=python) for process 407.
#
# This is a direct, hand-verified port of AsanIdentityGate.lean's
# `reachesApprovalDecide` — not an independent reimplementation. Theorem 3
# in that file (`reachesApprovalDecide_iff`) proves `reachesApprovalDecide`
# agrees with `reachesApproval`, the Prop-valued spec that Theorems 1/2 are
# about. This function must stay logically identical to
# `reachesApprovalDecide`'s four lines; if the Lean definition changes, this
# file needs the matching change, and the traceability that theorem gives us
# is only as good as this function actually staying in sync with it.
#
# Ported this way (Python, via git_call) rather than as a compiled Lean
# binary in a custom Docker image because Corezoid's git_call node schema
# only accepts lang in {js, python, golang} — there is no Dockerfile option,
# confirmed against this plugin's push-process JSON-schema validation
# (json-schema/logics/api_git.json), which hard-rejects anything else before
# the push ever reaches Corezoid.


def handle(data):
    gated = data.get("gated")
    fc = data.get("fc")
    recheck = data.get("recheck")

    if fc not in ("Verified", "Unverified") or recheck not in ("Verified", "Unverified"):
        raise ValueError(
            f"fc/recheck must each be 'Verified' or 'Unverified', got fc={fc!r} recheck={recheck!r}"
        )

    if gated:
        data["approved"] = fc == "Verified" or recheck == "Verified"
    else:
        data["approved"] = True

    return data
