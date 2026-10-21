# Finants — project orientation

Personal/household budgeting: known recurring income/expenses + imported
actual transactions → projected balances and a health report.
Forecasting-first, not envelope budgeting. A Red Ant AI experiment
(sibling of ../anthill — same stack and conventions, crib freely).

Stack: **Rails 8.1 + Postgres + Hotwire (Turbo/Stimulus) + importmap +
Tailwind 4 (tailwindcss-rails standalone CLI) + daisyUI 5** (emerald
light theme default, forest dark via prefersdark). Target host: Render
free web service + Neon free Postgres.

Read `PLAN.md` first — it tracks build phases and open decisions.

## Commands

- `bin/dev` — dev server (Puma :3000 + tailwind watch via foreman)
- `bin/rails db:prepare` — create/migrate dev DB (serves primary +
  solid_* connections)
- `bin/rails db:seed` — dev login `admin@finants.test` / `password`
- `bin/rails test` — test suite (Rails default test-unit)
- `bin/rails tailwindcss:build` — one-off CSS build
- `npm install` — required once so `@plugin "daisyui"` resolves
  (daisyui is a devDependency; node_modules is gitignored)
- Gems install to `vendor/bundle` (`bundle config path` set in
  `.bundle/config`) — the rbenv system gem dir is not writable.
- If `npm` fails with EACCES on the cache dir, prefix with
  `npm_config_cache=/tmp/npm-cache-finants`.

## Conventions

- daisyUI 5 via `@plugin "daisyui"` in `app/assets/tailwind/application.css`;
  invoke the **daisyui** skill before writing markup.
- Red Ant branding: `ant_icon` helper (SVG partial in
  `app/views/shared/_ant_icon.html.erb`) + `finants_wordmark` helper —
  "Ant" rendered in brand red `#FF2A00` (hard-coded, not `text-primary`,
  since the theme primary is green).
- Single household: no signup surface. Users created by admins (or seed).
- Money is integer cents, signed (+ in / − out), `amount_cents`. AUD.
- Accounts have nullable `owner` (user FK) — null means joint. Views
  default to pooled household.
- Transfers are two transactions linked by `transfer_pair_id`,
  excluded from income/expense rollups.
- Recurring rules forecast; they never auto-post actuals. Actuals link
  via `transactions.recurring_rule_id`.
- Create/edit happens in a right-side drawer (anthill pattern:
  `drawer drawer-end` + `redirect_back_to_page`).
- Archive = `active: false`; domain rows are never deleted.

## UX patterns (keep them consistent)

- **Drawers**: one `.drawer` wrapper per `.drawer-side`. Two sides under
  one wrapper means *every* toggle opens *both* — the later one wins
  and hides the intended drawer (this bug bit twice).
- `data-controller="drawer-open"` + `data-drawer-open-open-value` on the
  `.drawer-toggle` opens a drawer from a URL param (`?edit=`, `?new=`).
- **Div balance in index templates**: `.drawer` → `.drawer-content` →
  `.card`… → close card → close drawer-content → `.drawer-side` → close
  `.drawer`. A missing `</div>` nests `.drawer-side` inside the scroll
  pane — the overlay covers the page (can't scroll) and the panel
  vanishes (this exact bug happened).
- **Filters** live in a drawer too (`filter-drawer`, `sm:w-80`), opened
  by a "Filters (n)" button showing the active-filter count — never an
  inline filter bar.
- **Pagination**: any transaction list gets 100-row pages
  (`TransactionsController::PAGE_SIZE`) with Newer/Older footer links
  that preserve every filter param. Long lists are always paginated.
- **Tabs**: `tabs tabs-border` inside the card's bordered header
  (`border-b border-base-300 px-1`), Active/Paused/Detected style.
- **Helpers render markup**: `money`/`signed_money` return `<span>`s —
  never interpolate them into HTML attributes (`title="..."` breaks on
  the inner quotes; use `number_to_currency` inside attributes).
- **Optional partial locals**: read via `local_assigns[:x]` with a
  default — every caller must not be forced to pass every local
  (`suggested`, `once_rules` broke pages that didn't pass them).
- **Mobile**: `mobile_nav "key", path` + `content_for :mobile_action`.

## Forecast model semantics

- Three bases: `:rules` ("Best case" — scheduled items only),
  `:hybrid` ("Most likely" — rules + residual drift, the default),
  `:history` (raw net rate, not surfaced in UI toggles).
- Seeds are real balances; settle rules pay `-bal` of the card each
  occurrence and record `settlement_amounts` for display.
- Drift excludes: transfer pairs, rule-matched payees, one-off-flagged
  categories (`exclude_from_forecast`), rare-payee outliers, and any
  positive rows on loans/settle targets (debt plumbing, not income).
- In `:rules` mode settle targets still accrue *real drift* (the
  balance is measured data), but the card's own charge-rule deltas are
  skipped to avoid double-counting.
- Loan interest is an accrual — never cashflow/health spend. Principal
  repayments are real cash outflow through the liquid leg.
- Card payments and loan repayments are deliberately NOT paired (real
  outflow); only liquid↔liquid transfers pair as internal.
- "Ongoing rate" = regression slope over the back 60% of the series —
  a whole-span fit smears one-time stock events (the card payoff).

## House data notes

- Session cookie is `finants_session_id` (Anthill shares localhost's
  `session_id` — collision logged you out).
- Income rule payees must match *bank text* ("WAGES IOOF SERVICE CO"),
  not friendly names — a friendly label masks nothing.
