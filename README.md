# Finants

Household budgeting and cashflow forecasting for the Red Ant AI
experiments. Known recurring income/expenses + imported bank
transactions → projected balances, cashflow alerts, and a health
report built on real data, not invented estimates.

## Stack

- Rails 8.1, Postgres, Hotwire (Turbo + Stimulus), importmap
- Tailwind 4 (tailwindcss-rails standalone CLI) + daisyUI 5
- Test: Rails default test-unit (`bin/rails test`)

## Develop

```bash
bundle install        # gems install to vendor/bundle
npm install           # once, so the daisyui plugin resolves
bin/rails db:prepare  # create + migrate dev DB
bin/rails db:seed     # admin@finants.test / password
bin/dev               # Puma :3000 + tailwind watcher
```

## Seed data

`db/seeds.rb` is prod-safe: an admin user plus the starter category
taxonomy — no accounts, balances, or transactions. Prod credentials
come from `FINANTS_ADMIN_EMAIL` / `FINANTS_ADMIN_PASSWORD` env vars.

## How it works

- **Accounts** — liquid (cash/savings), credit, and loan kinds.
  Nullable `owner` = joint household account.
- **Transactions** — manual or imported (HSBC/Qudos/Amex CSV/XLSX
  presets in `CsvImport`), deduped by import hash, auto-categorised by
  learned payee rules. Paired via `transfer_pair_id` when internal.
- **Recurring rules** — the forecast schedule. Frequency + anchor
  date; `include_in_hybrid` selects which rules feed the realistic
  projection. `settle` kind dynamically pays a card's projected
  balance each cycle.
- **Forecast** (`app/services/forecast.rb`) — seeds real balances,
  walks forward applying rule deltas, settle payments, and residual
  drift from trailing-window actuals. Two UI bases: *Best case* (rules
  only) and *Most likely* (rules + real-life residual).
- **Health** (`app/services/health_report.rb`) — bill coverage vs
  income, monthlyized spend by category, income vs spend trend, and
  income-by-category including projected months.
- **Smoothing** (`app/services/smoothing_suggestions.rb`) — finds cash
  troughs under the warn threshold and suggests moving big outflows to
  after payday.

More detail in `.devin/skills/finants/SKILL.md`.
