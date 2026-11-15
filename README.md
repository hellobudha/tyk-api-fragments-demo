# One baseline, every API: a walkthrough of Tyk API Fragments

A runnable story about **API Fragments**, the shared-configuration feature added in
Tyk Dashboard 5.16.0. It takes about ten minutes and runs on your laptop with Docker.

You will watch a bank find out that two of its three APIs no longer follow its own security
baseline, fix all of them without touching the teams' work, roll out a partner launch with one
request, fail to break production three different ways, and onboard a fourth team that never
gets the chance to drift.

## The problem

Every organisation with more than a handful of APIs has settings that are meant to be the same
everywhere: which browser origins may call the APIs, how tokens are validated, which TLS
settings the upstreams use, what the rate limit is, which headers every response carries.

Until now each of those settings lived **inside each API definition**. That has three costs,
and they grow with every API you add.

| Cost | What it looks like |
| --- | --- |
| **Drift** | A team changes its copy during an incident and never changes it back. The baseline is right in the wiki and wrong in production. |
| **Slow change** | Allowing one new partner origin means one ticket, one review and one deploy per API. A one-line decision becomes a quarter of work. |
| **No answer** | "Which APIs still have the old setting?" can only be answered by opening every API. |

The usual workarounds each leave a gap. API Templates set the right values on day one, then the
copy belongs to the API and drifts. CI scripts that stamp configuration into definitions work
until somebody edits an API in the Dashboard. Gateway-wide settings apply to everything, with no
way to say "these 40 APIs, not those".

## What a Fragment is

A Fragment is a named piece of API configuration stored once in Tyk Dashboard. An API definition
holds a reference where the configuration would be:

```json
"cors": { "$ref": "fragment://cors-browser-apps" }
```

- **The Dashboard stores the reference and resolves it.** Tyk Gateway receives a complete
  definition and never sees a reference. In a distributed deployment MDCB (2.14.0 or later)
  resolves references for the Data Plane Gateways.
- **Changing the Fragment changes every API that references it,** and the Gateway reloads.
- **A change cannot break the APIs that use it.** The Dashboard validates every referencing API
  and API Template against the new value first, and rejects the change if any would be invalid.
- **A Fragment in use cannot be deleted.**
- **Ownership splits cleanly.** The platform team owns Fragments through the existing
  `api_assets` permission. API teams own the rest of each definition. Fields set by a Fragment
  are read-only in the API Designer and carry a *Shared configuration* badge.

Fragments work with Tyk OAS and Tyk Streams APIs.

## The scenario: Meridian Bank

Meridian Bank has a two-person platform team, led by Priya, and three API teams: Accounts,
Payments and Cards. A year ago each team pasted the bank's security baseline into its API:

1. **CORS**: only Meridian's own web app may call the APIs from a browser.
2. **Rate limit**: 20 requests per 10 seconds per API, to protect the shared core banking system.
3. **Security response headers**: three headers required by audit control SEC-14.

Then an auditor asks whether every API enforces it.

| Act | Script | What happens |
| --- | --- | --- |
| 0 | `demo/00-setup.sh` | Starts Tyk 5.16.0 and loads the three APIs as the teams wrote them. |
| 1 | `demo/01-the-drift.sh` | **The audit.** Payments allows any website. Cards has no security headers and ten times the rate limit. |
| 2 | `demo/02-extract.sh` | **Store it once.** Three Fragments are created and each API swaps its copy for a reference. All three APIs are back in line. |
| 3 | `demo/03-one-change.sh` | **Friday, 4pm.** A partner, NovaPay, must be allowed on every API by Monday. One request does it. |
| 4 | `demo/04-guardrails.sh` | **What if the one change is wrong?** A typo, a delete and a quiet opt-out are each refused. |
| 5 | `demo/05-new-team.sh` | **The fourth team.** The Loans API is created from a Template that carries the references, so it starts on the baseline and stays on it. |

Every act ends with the same audit table. It is not read from configuration: the browser columns
are live CORS preflight requests sent through the Gateway, so the table shows what a caller gets.

```text
API       our app   rogue site  NovaPay   sec hdrs  rate limit   from fragments
accounts  allowed   blocked     blocked   3 of 3    20 per 10s   0 of 3 blocks
payments  allowed   ALLOWED     allowed   3 of 3    20 per 10s   0 of 3 blocks
cards     allowed   blocked     blocked   0 of 3    200 per 10s  0 of 3 blocks
```

That is Act 1. By Act 5 there are four APIs, every row is identical, and every block comes from a
Fragment.

## Run it

You need Docker, `curl`, `jq`, and a Tyk Dashboard licence. Fragments are a Dashboard feature, and
the Dashboard is a licensed product. A free trial licence is available at
<https://tyk.io/self-managed-trial/>.

```bash
cp .env.example .env
```

Put your licence in `.env` as `TYK_LICENSE_KEY`. The file is gitignored. Then:

```bash
./demo/00-setup.sh
```

```bash
./demo/01-the-drift.sh
```

Carry on through `02` to `05`. Each script pauses between beats so you can talk, and prints the
request it is about to make. To run everything without pauses:

```bash
./demo/run-all.sh
```

Other commands:

| Command | Use |
| --- | --- |
| `./demo/audit.sh` | Print the audit table at any point. |
| `./demo/00-setup.sh` | Run again to rewind to the start of Act 1. |
| `./demo/reset.sh` | Remove the stack and its data. |

The stack uses Dashboard port 3100 and Gateway port 8280 so that it does not collide with another
Tyk install. Change them in `.env`. The Dashboard login is written to `.demo/login.txt`. After
Act 2, open **Assets > Fragments** to see the usage list for each Fragment, and open any API to
see the *Shared configuration* badge.

## What to look at in the repository

| Path | Contents |
| --- | --- |
| `apis/before/` | The three APIs with pasted configuration, including the drift. |
| `apis/after/` | The same APIs with references. `diff` a pair to see the whole change. |
| `fragments/` | The three Fragments, as sent to `PUT /api/assets/{id}`. |
| `templates/` | The API Template that carries the references for new APIs. |
| `apis/new/loans.json` | Everything the fourth team had to write. |
| `demo/lib.sh` | The audit and the helpers. Read `audit()` to see how each column is measured. |

## The Dashboard API calls the walkthrough uses

| Call | Purpose |
| --- | --- |
| `PUT /api/assets/{id}` with `"kind": "fragment"` | Create or replace a Fragment. |
| `PUT /api/apis/oas/{apiId}` | Save an API whose definition contains `{"$ref": "fragment://<id>"}`. |
| `GET /api/apis/oas/{apiId}` | The stored definition, with references. |
| `GET /api/apis/oas/{apiId}?resolved=true` | The definition the Gateway runs. |
| `GET /api/apis/oas/{apiId}/fragments` | Every Fragment the API references, keyed by where it is used. |
| `GET /api/assets/{id}/apis` | Every API that references a Fragment. |
| `POST /api/apis/oas?templateID={id}` | Create an API from a Template, references included. |

## Things to know before you use Fragments for real

- The `$ref` must be the only key in its object. You cannot reference a Fragment and override one
  field next to it. Act 4 shows the error.
- A Fragment cannot reference another Fragment.
- A JSON merge patch (`PATCH`) merges into the existing object, so patching a `$ref` into a block
  that already has fields is refused for the same reason. Replace the block with `PUT`, or set the
  old fields to `null` in the patch.
- Tyk Classic APIs cannot use Fragments.
- APIs loaded straight into the Gateway from files or the Gateway API cannot use Fragments,
  because only the Dashboard and MDCB resolve references.
- Tyk Operator does not support Fragments. Tyk Sync 2.3.0 and later manages them as code and
  writes Fragments before the APIs that use them.
- If a Fragment sets client certificates or JWT scope-to-policy mappings, the Developer Portal
  cannot add that API to an API Product unless you use the Identity Provider Registry.
- Use a Fragment for a setting that must be the same everywhere. Use a Template for a starting
  value that teams are expected to change. Leave API-specific settings such as the listen path
  and upstream URL in the API.

## Versions and references

Tested with Tyk Dashboard v5.16.0 and Tyk Gateway (`tykio/tyk-gateway-ee`) v5.16.0. The secrets
and database password in `docker-compose.yml` are development defaults for a throwaway stack.

- [API Fragments documentation](https://tyk.io/docs/platform-management/api-fragments)
- [Tyk Dashboard 5.16.0 release notes](https://tyk.io/docs/developer-support/release-notes/dashboard)
- [API Templates documentation](https://tyk.io/docs/platform-management/api-templates)
