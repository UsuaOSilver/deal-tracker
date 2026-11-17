# Multi-Agent System Project Brief

**Date:** 2026-11-17 · **Author:** Nhat Anh Nguyen

## How to use this brief

Fill in sections 1, 2 and 5 first. They make about 80% of the architecture decisions. Leave an answer blank if you don't know it yet.

| Section | What it decides |
| --- | --- |
| 1. The job + 7. How you'll judge it | Whether the system works, and how to test it |
| 2. Shape of the work | One agent vs. a manager with workers vs. specialists |
| 3. Roles | The roster, the model for each agent, and their prompts |
| 4. Tools + 6. Risk | Tool access and human-approval rules |
| 5. Limits + 8. Integration | Hosting (Managed Agents, Agent SDK or your own loop) and scheduling |

---

## 1. The job

**Goal (one sentence):** What does the system produce, and for whom?

> Turn a plain shopping request from the owner ("any Crocs clog under $25 in sizes 4-5M, 4-5J, 7-8M, 12M") into working, tested price watches in the self-hosted tracker, so the owner gets a phone alert with a one-tap buy link when a deal appears.

The hourly price checks and alerts already run as deterministic code (changedetection.io plus headless Chrome). The agents only do the setup work that currently takes a person many manual steps: finding product pages, picking per-size item IDs, choosing the right filter for each store, and checking that the watch reads a real price.

**Examples.** Give 2–3 real requests and what a good output looks like. This is the most useful section.

| # | Input / request | What a good output looks like |
| --- | --- | --- |
| 1 | "Watch the Crocs Off Grid Clog, any color, sizes M4, M5, M7, M8, M12, alert under $25." | One Walmart watch using the cheapest-in-stock-in-size jq filter, first check returns a number (e.g. `26.99`), condition `< 25`, plain-text alert with buy link. Stores that block fetching are reported, not watched. |
| 2 | "Gaggia descaler 250 ml, 1, 2 or 3 pack, under $7 per bottle." | One watch per pack size with target = 7 × bottles (3-pack < $21, 2-pack < $14). Packs over $7 per bottle (6-pack, 12-pack) are listed as skipped, with the reason. A pack with no price on its page is flagged. |
| 3 | "RTX 5070 laptop, 32 GB RAM, 1–2 TB, shortlist a few and set targets." | 3–5 models with sources for the prices, a target per model a little under the best recent price, a watch per model per working store, and current price for each. |

**What "done" means.** How do you tell a good result from a bad one? Write checkable criteria.

- [ ] Every watch it creates completes a first check with no error and returns a price (or an explicit "none in stock in your sizes").
- [ ] The captured price matches the price shown on the live product page for the stated size and pack.
- [ ] Each alert names the item and includes a working buy link.
- [ ] Stores that block automated fetching are reported as blocked, never worked around.
- [ ] Nothing is bought, and no store login, card or payment data is stored anywhere.
- [ ] Watch count stays within `PAGE_WATCH_LIMIT` (50).

---

## 2. Shape of the work

This section decides whether you need one agent or several.

| Question | Answer |
| --- | --- |
| Can the work split into independent pieces (sources, items, stores)? How many pieces per run? | Yes. Each store × product is independent. A typical request is 2–8 pieces (e.g. 4 Crocs models × 2 stores). |
| Roughly how much reading compared with hard reasoning? | Mostly reading. Product pages are 1–2 MB of HTML; the useful part is a small embedded JSON block. Reasoning is light: match sizes, pick a filter, set a target. |
| Does it handle one item at a time, or many items per run? | Usually a handful of items per request, a few requests per week before big sales. |
| Do some sub-tasks need different skills, tools or permissions? | Yes. Web search and page reading are read-only; creating watches writes to the tracker; buying is human-only. |
| Would one agent's context fill up with reading on its own? | Yes, if it reads raw pages. A single page snapshot can exceed the useful context, so page reading should happen in workers that return a few lines. |

**Rules of thumb:**
- One question at a time, no natural split → **one agent** with a top model and higher effort.
- Many independent pieces, or heavy reading → **a manager that delegates to copies of itself**, then adds a cheaper worker model for the reading.
- Sub-tasks that need different skills or permissions → **dedicated specialists**.

**Decision:** a manager plus cheap page-reader workers. Watch creation stays with the manager, so only one agent can write to the tracker. No buying agent.

---

## 3. Roles

Fill this in only if section 2 points to multiple agents.

| Agent | Responsibility (one line) | Receives | Returns (format) | Tools / data | Must NOT touch | Model tier (top / mid / cheap) |
| --- | --- | --- | --- | --- | --- | --- |
| Manager | Plans, delegates, verifies, combines the results | Owner's request, current watch list, store status table | Summary for the owner: watches created, current prices, skipped items with reasons | Tracker API (read/write), web search, worker dispatch | Store checkout, payment data, Telegram token, git push | top |
| Page reader | Extracts size/color variants, item IDs, prices and stock from one product or search page | One page URL or a saved snapshot, the sizes and pack sizes wanted | JSON list: `{item_id, name, color, size, price, in_stock, url}` | Tracker snapshot API (read-only), temporary watch on one URL | Creating permanent watches, any write outside its temp watch | cheap |
| Verifier | Confirms a new watch reads the right price | Watch UUID, expected item and size | `pass` / `fail` + captured price + reason | Tracker API (read-only) | Editing watches | cheap |

**What the manager keeps for itself.** Typically verification, combining results, and decisions with real consequences.

> Choosing targets and filters, creating and deleting watches, deciding a store is blocked, and the final report. It never buys.

**What every brief from the manager to a sub-agent must include.** The goal, the context the sub-agent needs, what's out of scope, and the report format.

> The exact URL, the sizes/packs wanted, the return JSON schema, a reminder that bot checks and access denials are reported (not bypassed), and a cap of one temporary watch that it must delete when done.

---

## 4. Tools, data and access

| System / data source | What it's used for | Read / write | Credential |
| --- | --- | --- | --- |
| changedetection.io API (`127.0.0.1:5000/api/v1`) | Create, update, recheck and read watches and snapshots | Read/write (manager); read (workers) | API key from the tracker datastore |
| Headless Chrome container | Loads store pages for the tracker | Indirect, through the tracker only | None, no published port |
| Web search | Find product pages and recent prices | Read | Search tool access |
| Telegram bot | Alerts to the owner's phone | Write (sent by the tracker, not by agents) | Bot token in tracker settings |
| GitHub repo `UsuaOSilver/deal-tracker` | Docs and config changes | Write | Owner's SSH key |
| Store checkout | Buying | None for agents | None |

**Actions that need human approval** (sending, deleting, spending, deploying):

- Any purchase or anything that spends money (agents never do this).
- Deleting watches the owner created, or more than 5 watches in one run.
- Changing global notification settings or the Telegram address.
- Pushing to GitHub, rebuilding or upgrading the containers.
- Adding a store that needs a login, cookies or a bot-check workaround (answer is no by default).

---

## 5. Limits

| Limit | Answer |
| --- | --- |
| Cost budget (per run / per month) | |
| Speed: does a person wait for the answer, or does it run in the background? Target time? | The owner waits, but minutes are fine. Target: under 10 minutes for a request covering about 5 items. |
| How often it runs: on demand, scheduled, or triggered by an event? | On demand when the owner adds items. Price checks stay hourly in the tracker, without agents. |
| Data rules: privacy, compliance, retention (ZDR, PII)? | No payment data or store logins anywhere. Secrets stay in `.env` and the tracker datastore, never in prompts, logs or git. |
| Hosting: OK for Anthropic to host the agent loop and sandbox, or must it run on your own infrastructure? | Own machine. The tracker is bound to 127.0.0.1, so the agent loop must run locally (Agent SDK or own loop). |
| Preferred language / existing stack | Python 3.11, Docker Compose on WSL2 Ubuntu. |

---

## 6. Risk and failure

| Question | Answer |
| --- | --- |
| What happens if the output is wrong? How bad is it? | A wrong watch means a missed deal or a false alert. Low harm on its own, because a person taps to buy and sees the real price first. It would be serious only if auto-buy is added later. |
| Can mistakes be caught and undone (tests, review, rollback)? | Yes. Each watch is checked once right after creation, watches can be edited or deleted, and config lives in git. |
| Known edge cases and likely failure points | Stores blocking fetches (Amazon, Best Buy, eBay, Kohl's, Dick's, Macy's, Academy). Prices shown only after the browser renders them (Target). One price per product, not per size (crocs.com). Listings with no price (unavailable). Page structure changes breaking a filter. Page fetches skip TLS verification, so a captured price is a hint, not proof. Sold-out sizes. Toddler sizes passing a price filter. |
| When should it stop and escalate to a human? | A store blocks access; a page shows no price; captured and visible prices disagree; a request would exceed the watch limit; anything involving login, payment or spending. |

---

## 7. How you'll judge it

**Test set.** Start with 10–30 realistic tasks that have known good answers. Save them somewhere and link to them here:

> To create: `docs/agent-tests.md`, seeded with the requests from this project (laptops, Crocs by model and size, any Crocs clog, Gaggia packs).

| Measure | Baseline today | Target |
| --- | --- | --- |
| Quality (pass rate against the "done" criteria) | | ≥ 90% |
| Cost per completed task | | |
| Time per task | | < 10 min per 5-item request |

**What you're comparing against:** a human, the current process, or a single agent.

> The current process: watches set up by hand through the tracker API, one store and size at a time. Also a single agent without workers, to check the extra agents are worth it.

---

## 8. Integration

| Question | Answer |
| --- | --- |
| What starts a run? (a user, an API call, Slack, a schedule) | The owner, from the terminal. A Telegram command could come later. |
| Where do results go? (files, a PR, a database, a message) | New watches in the tracker, plus a short summary to the owner. |
| What logging, tracing or monitoring do you need? | A log of each tracker API call (watch created, changed or deleted), and the tracker's own Docker logs. No secrets in logs. |
| Who owns it in production? | Nhat Anh Nguyen |

---

## Open questions

- Monthly cost budget for agent runs.
- Whether to add a Telegram trigger ("watch X under $Y") or keep requests to the terminal.
- If auto-buy is ever built: the spending cap, and the per-item approval step.
- Which other Crocs stores to try for junior sizes (4-5J).
