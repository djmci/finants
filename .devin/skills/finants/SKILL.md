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
