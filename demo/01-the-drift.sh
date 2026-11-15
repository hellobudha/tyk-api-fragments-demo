#!/usr/bin/env bash
# Act 1: three teams, three copies of the same rules, and they no longer match.
. "$(dirname "$0")/lib.sh"; need_state

act "Act 1: The audit"
say "Meridian Bank has one security baseline and three API teams.
Each team pasted the baseline into its own API definition a year ago.
Today the auditor asks one question: do all your APIs enforce it?"
pause

say "Nobody can answer from the Dashboard without opening every API, so we ask the Gateway."
show "./demo/audit.sh"
audit "${APIS[@]}"
pause

say "${B}What the audit found${N}
  ${R}payments${N}  Someone set allowedOrigins to \"*\" during an incident and never put it back.
            Any website can now call the Payments API from a customer's browser.
  ${R}cards${N}     The security headers were never added, and the rate limit is ten times the standard.
  ${G}accounts${N}  Correct. It is also the only one.

The baseline is right in the wiki and wrong in two of three APIs.
At 3 APIs this is a bad afternoon. Meridian has 140."
say "Here is the block every team copied, as the Payments team has it today:"
show "jq '.\"x-tyk-api-gateway\".middleware.global.cors' apis/before/payments.json"
jq -c '."x-tyk-api-gateway".middleware.global.cors' "$ROOT/apis/before/payments.json"

say "Next: ${B}./demo/02-extract.sh${N}"
