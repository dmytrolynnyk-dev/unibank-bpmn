import Lean.Data.Json
import AsanIdentityGate

/-!
Git Call entrypoint for `reachesApprovalDecide` (AsanIdentityGate.lean).

Contract assumed here (per JSON-RPC 2.0, "handle(data)"): one JSON-RPC request
object arrives on a single line of stdin, one JSON-RPC response object is
written to stdout.

  Request:  {"jsonrpc":"2.0","method":"handle","id":<any>,
             "params":{"gated":true,"fc":"Verified","recheck":"Unverified"}}
  Response: {"jsonrpc":"2.0","id":<same id>,"result":{"approved":true}}
         or {"jsonrpc":"2.0","id":<same id>,"error":{"code":-32602,"message":"..."}}

STATUS / CAVEAT: written without a Lean toolchain to compile or run it, and
without a confirmed reference of Corezoid Git Call's *actual* request/response
shape for a custom-Dockerfile node — the field names above (`params`, `id`,
the exact error-code convention) are a reasonable guess at standard JSON-RPC
2.0, not a verified copy of what Corezoid sends. Before trusting this: compare
against a working Git Call example (e.g. whatever the AntiFraud/RTP Lean setup
already uses) and correct the request/response shape to match exactly.
-/

open Lean

private def parseOutcome (s : String) : Except String CheckOutcome :=
  match s with
  | "Verified"   => .ok .Verified
  | "Unverified" => .ok .Unverified
  | other        => .error s!"unknown CheckOutcome value: {other}"

/-- Pure request handler: no IO, just JSON in, JSON-or-error out. Kept separate
    from `main` so it stays easy to unit-test once a toolchain is available. -/
def handle (params : Json) : Except String Json := do
  let gated ← params.getObjValAs? Bool "gated"
  let fcStr ← params.getObjValAs? String "fc"
  let recheckStr ← params.getObjValAs? String "recheck"
  let fc ← parseOutcome fcStr
  let recheck ← parseOutcome recheckStr
  let approved := reachesApprovalDecide gated fc recheck
  return Json.mkObj [("approved", Json.bool approved)]

private def errorReply (id : Json) (message : String) : Json :=
  Json.mkObj [
    ("jsonrpc", Json.str "2.0"),
    ("id", id),
    ("error", Json.mkObj [("code", Json.num (-32602)), ("message", Json.str message)])
  ]

private def okReply (id : Json) (result : Json) : Json :=
  Json.mkObj [("jsonrpc", Json.str "2.0"), ("id", id), ("result", result)]

def main : IO Unit := do
  let stdin ← IO.getStdin
  let line ← stdin.getLine
  match Json.parse line with
  | .error e => IO.println (errorReply Json.null s!"invalid JSON request: {e}").compress
  | .ok request =>
      let id := (request.getObjVal? "id").toOption.getD Json.null
      match request.getObjValAs? Json "params" with
      | .error e => IO.println (errorReply id s!"missing params: {e}").compress
      | .ok params =>
          match handle params with
          | .error e => IO.println (errorReply id e).compress
          | .ok result => IO.println (okReply id result).compress
