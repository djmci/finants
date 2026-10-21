# Seed — first admin + starter categories. Idempotent, safe to re-run.
# Dev login: admin@finants.test / password
# Prod: override via FINANTS_ADMIN_EMAIL / FINANTS_ADMIN_PASSWORD.

admin = User.find_or_initialize_by(email_address: ENV.fetch("FINANTS_ADMIN_EMAIL", "admin@finants.test"))
admin.update!(name: "Household admin", role: "admin",
              password: ENV.fetch("FINANTS_ADMIN_PASSWORD", "password"))

{
  "income" => %w[Salary Interest Dividends Other Tax\ refund],
  "expense" => %w[Communication Council\ rates Eating\ Out Energy Entertainment
                  Giving Groceries Health Household Insurance Internet
                  Music\ lesson Other Pet\ care Reimbursement Rent/Mortgage School Sport
                  Subscriptions Transfer Transport Travel Union Utilities]
}.each do |kind, names|
  names.each do |name|
    Category.find_or_create_by!(name:, kind:) { |c| c.active = true }
  end
end
