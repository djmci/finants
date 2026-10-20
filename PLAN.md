# Finants — build plan

Personal/household budgeting. Rails 8.1 + Postgres + Hotwire + Tailwind 4 +
DaisyUI 5 — same stack and conventions as ../anthill, crib freely.

Core idea: known recurring income/expenses + imported actual transactions →
projected balances and a health report. Forecasting-first, not envelope
budgeting.

Status legend: `[ ]` pending · `[~]` in progress · `[x]` done

## Decisions locked

- **Stack**: identical to anthill — Rails 8.1, importmap, Hotwire (Turbo +
  Stimulus), tailwindcss-rails (standalone CLI), DaisyUI 5 via
  `@plugin "daisyui"` (npm i needed before `tailwindcss:build`).
- **DB**: Postgres (local Homebrew PG17; Neon free tier in prod).
- **Hosting**: Render free web service (512MB, sleeps idle, wakes in
  seconds). Dockerfile deploy. DB on Neon — Render's free PG expires 30d.
- **Auth**: Rails 8 built-in authentication generator. No public signup —
  first user seeded, members created by admins.
- **Household**: single household, small member list (anthill's single-org
  model). Not multi-tenant.
- **Money**: integer cents, signed (+ in / − out), `amount_cents`. AUD
  default.
- **Accounts**: `kind` enum (everyday/savings/credit/cash/loan),
  `opening_balance_cents`, `active`, nullable `owner` FK → users.
  Loans/mortgages are just accounts with a negative (owed) balance.
  Repayment = transfer into the loan (correctly excluded from spend:
  principal is a net-worth transfer). Interest = negative txn inside
  the loan account categorised "Mortgage Interest" → lands in spend
  reports. Both halves get recurring rules. Later: rate tracking,
  auto interest estimate (rate × balance / 365), offset awareness,
  amortisation-vs-actual drift in the health report.
  owner=null means joint. Balance = opening + Σ transactions. Views default
  to pooled household; mine/yours/joint and per-account filters.
- **Transfers**: two linked transactions via `transfer_pair_id`; excluded
  from income/expense rollups.
- **Categories**: `kind` (income/expense), optional `parent_id` for
  grouping, colour. Nullable on transactions → "uncategorised" worklist.
- **Transactions**: `posted_on`, payee, `amount_cents`, account, category,
  `recurring_rule_id` (nullable — actual matched to a known bill),
  `import_hash` (dedupe), `import_id` (batch), user (entered by).
- **RecurringRule**: payee, account, category, amount, frequency
  (weekly/fortnightly/monthly/yearly × interval), start_on, end_on
  nullable, kind (income/expense), active. Rules forecast; they never
  auto-post actuals.
- **Auto-categorisation**: payee → category rules learned from manual
  categorisation; applied on import and manual entry, always overridable.
- **Forecast**: pure `Forecast` service (anthill phase-9 pattern:
  bulk-loaded, all cell math in one place) — current balances + rule
  occurrences + estimated discretionary spend → daily projected balance
  per account and combined, ~12mo horizon. Discretionary estimate =
  historical average non-recurring spend per category, overridable.
- **Health report**: computed, not stored — min projected balance + its
  date, first-negative date, upcoming-bill coverage, income-vs-spend
  trend, category actuals vs estimates.
- **Imports**: header-signature presets for HSBC / Qudos / Amex (identify
  by header row, like anthill's Harvest importer — never by filename),
  generic column-mapper fallback, import batches (a bad import deletable
  wholesale), dedupe via hash of (account, date, amount, description).

## Phase 0 — skeleton [x]

- [x] `rails new . --database=postgresql` (Rails 8.1.3, Ruby 3.3.11)
- [x] `bundle config path vendor/bundle` (rbenv gem dir not writable)
- [x] solid_cache/queue/cable + `db:prepare`
- [x] tailwindcss-rails + DaisyUI 5.7.50 via npm + `@plugin "daisyui"`
      (emerald default, forest prefersdark — anthill's themes are brand
      red; Finants goes green-for-money)
- [x] `rails generate authentication` + name/role on users, dev seed
- [x] Red Ant branding: ant icon partial, `ant_icon`/`finants_wordmark`
      helpers ("Ant" hard-coded #FF2A00 — theme primary is green)
- [x] `.devin/skills/finants/SKILL.md`
- [x] GitHub repo `djmci/finants` (private) + initial push

## Phase 1 — domain core [x]

- Models: Account, Category, Transaction (+transfer pairing), Import
  (table + FKs now, importer UI in phase 3).
- CRUD in anthill's right-drawer pattern (`drawer drawer-end` +
  `redirect_back_to_page`, `drawer_open` Stimulus).
- `DollarField` concern: form-facing dollars over `*_cents` columns.
- Account show: running balance column, payee search, uncategorised
  filter, txn drawer.
- Transactions index: account/owner/payee/uncategorised filters +
  transfer drawer (paired signed txns).
- Dashboard: account cards + uncategorised count.
- Fixtures + model/request tests (transfer pairing, balance math,
  category nesting, direction sign, auth redirects) — 40 runs green.

## Phase 2 — UI shell [x]

- daisyUI layout cribbed from anthill: collapsible sidebar (`sc` cookie),
  mobile navbar + `mobile_nav`/`:mobile_action` slots, flash toasts,
  footer credit.
- Themes emerald/forest via `data-theme` + `theme` cookie; `m` key or
  profile-menu toggle (client-side cookie, no endpoint needed).
- Keyboard shortcuts: `g d/t/a/c` nav, `n` new transaction, `m` theme,
  `?` help modal, esc closes drawers.
- Dashboard: account cards + uncategorised count (forecast lands in
  phase 5).

## Phase 3 — CSV import [ ]

- Upload → header sniff → preset detection → preview → commit.
- Presets: HSBC AU, Qudos, Amex AU. Generic mapper fallback for others.
- Batches: `imports` table; delete a batch to undo.
- Dedupe on `import_hash`; flag near-dupes (same date+amount).
- Payee → category rule learning.
- Note: HSBC online CSV only reaches ~90 days back; Amex ~6 statements.

## Phase 3b — PDF statement import [ ]

- HSBC online banking caps CSV at ~90 days; Qudos online banking is
  PDF-only (secure mail). PDF import is how real history gets in.
- `pdf-reader` text extraction of statement transaction tables; per-bank
  layout parser keyed off detected statement header.
- Same preview/dedupe/batch pipeline as CSV.

## Phase 4 — recurring rules [ ]

- RecurringRule CRUD + pure occurrence-generation service.
- Actual → rule match suggestions by payee + amount when reviewing
  transactions; linking sets `recurring_rule_id`.
- Upcoming-bills list (next 30 days) — first consumer of occurrences.

## Phase 5 — forecast + dashboard [ ]

- `Forecast` service: pure, bulk-loaded.
- Dashboard: account balances, projected-balance chart (per account +
  combined), next-30-days bills/income list, horizon selector.
- Discretionary estimate from category history.

## Phase 6 — health report [ ]

- Computed report page: min projected balance + date, first-negative
  date, upcoming-bill coverage vs income, income-vs-spend trend,
  category actual vs estimate.

## Phase 7 — ship [ ]

- Dockerfile tuned for Render (nodejs in build stage for DaisyUI).
- Neon `DATABASE_URL` serving all solid_* connections via `db:prepare`.
- README + env vars (`DATABASE_URL`, `SECRET_KEY_BASE`, `APP_HOST`).

## Testing (continuous, all phases)

- Minitest + fixtures. Model tests per phase for invariants: transfer
  pairing, balance math, import dedupe, occurrence generation, forecast
  math, rule learning.
- Request tests: auth redirects, CRUD happy paths.
- `bin/rails test` green before each phase commit.
- CI: GitHub Actions like anthill (Postgres service, `db:prepare`,
  `rails test`, `npm ci` + `tailwindcss:build`).

## Later / not scheduled

- Bank API sync (Up Bank or similar) — CSV/PDF first.
- Category budget targets once forecasting proves out.
- MCP endpoint like anthill's `/mcp` (agents log transactions).

## Conventions cribbed from anthill

- Right-side drawer for create/edit + `redirect_back_to_page` (strips
  drawer params, accepts flash kwargs).
- importmap (no JS bundler); Stimulus controllers; Turbo frames/streams.
- daisyUI 5 `@plugin "daisyui"` in `app/assets/tailwind/application.css`;
  light default + dark prefersdark themes; invoke the **daisyui** skill
  before writing markup.
- Gems to `vendor/bundle`; `npm_config_cache=/tmp/...` workaround if npm
  hits EACCES on the cache dir.
- `bin/dev` via foreman: Puma :3000 + tailwind watch.
- Archive = `active: false`, never delete domain rows.

## Open questions / assumptions

- Deepest cheap history per bank: HSBC 90d CSV then PDF statements (7yr);
  Qudos PDF via secure mail / app CSV; Amex ~6 statements CSV.
- Fortnightly frequency needed for AU pay cycles — included in rule enum.
- PDF layout parsing is per-bank fiddly; phase 3b estimates one parser
  each for HSBC + Qudos, extendable.
