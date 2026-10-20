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

## Phase 3 — CSV import [x]

- Upload → header sniff → preview → commit; `imports.payload` stores the
  raw CSV so preview/commit are separate steps.
- `CsvImport` service: presets detected by header signature — **Qudos**
  (`Effective Date,Entered Date,Transaction Description,Amount,Balance`
  — Entered Date is the populated one) and **HSBC** (xlsx extract
  `Transaction Date/Detail/Amount/Balance`, plus debit/credit CSV
  variant) verified against real files; Amex preset is still a guess
  pending a real export.
- **xlsx uploads** via `creek`: sheet picker for multi-sheet workbooks,
  binary `imports.payload`, typed cells (real dates/numbers), Excel
  serial-date fallback.
- Batches: draft/committed `status`; deleting an import cascades its
  transactions (undo). Dedupe via `import_hash` (account + raw row),
  in-batch too — re-uploading the same file is a no-op.
- Payee → category `payee_rules`: learned on manual categorisation
  (after_save on category change), substring match longest-first,
  applied at commit.
- Tests: preset detection, sign flip, debit/credit, dedupe, undo,
  rule learning — 53 runs green.
- Note: HSBC online CSV only reaches ~90 days back; Amex ~6 statements.

## Phase 3b — PDF statement import [ ]

- HSBC online banking caps CSV at ~90 days; Qudos online banking is
  PDF-only (secure mail). PDF import is how real history gets in.
- `pdf-reader` text extraction of statement transaction tables; per-bank
  layout parser keyed off detected statement header.
- Same preview/dedupe/batch pipeline as CSV.

## Phase 4 — recurring rules [x]

- `RecurringRule`: payee, account, category, kind (expense/income/
  transfer — transfer carries `to_account` for the mortgage-repayment
  pattern), amount, frequency (weekly/fortnightly/monthly/yearly) ×
  `every` N, start_on, end_on nullable, active (pause/resume).
- `Recurring` — pure occurrence service: anchored advance (weekly/
  fortnightly by days; monthly clamps day-of-month then resumes anchor
  day; yearly), range-scoped, `end_on` aware.
- Auto-match: `before_validation` on Transaction links a matching
  active rule (same account, same amount magnitude, rule payee as
  substring of txn payee, longest wins). Covers manual entry + imports.
- `/recurring_rules` drawer CRUD + next-occurrence column; ↻ badge on
  matched transactions; dashboard "Upcoming — next 30 days" panel.
- Tests: occurrence math (clamp, intervals, mid-range anchor, end_on),
  match_for, auto-link — 68 runs green.

## Phase 5 — forecast + dashboard [x]

- `Forecast` service: pure, bulk-loaded.
  - Seed = opening balance + actual txns before horizon start.
  - Daily series = seed + rule occurrences + discretionary drift.
  - Transfer rules debit source / credit target (household total unaffected).
  - Discretionary v1 = trailing-90d mean daily outflow per account,
    excluding transfer pairs and rule-linked txns.
  - `series` / `combined` / `minimum` APIs; negative balances handled
    (loan accounts).
- Dashboard: balance chart (90d actual solid → projection dashed, today
  seam, signed y-axis with zero line), per-account selector, 3/6/12mo
  horizon tabs, projected-end and floor-balance stats; Upcoming panel
  moved below it.
- Tests: rule descent, transfer neutrality, discretionary drift,
  rule-link exclusion, floor detection — 73 runs green.

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

- **Inter-account transfer pairing on import** — bank exports contain
  legs like "Transfer to SAV 02348xxx" that are movements between own
  accounts, not real spend/income. A matching pass could link
  opposite-signed rows on same/adjacent dates across accounts into
  `transfer_pair_id`, or a "transfers" review bucket to suppress them
  from spend reports.
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
