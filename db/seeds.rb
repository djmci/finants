# Dev/test seed — first household member + starter categories.
# Idempotent, safe to re-run. Login: admin@finants.test / password

admin = User.find_or_initialize_by(email_address: "admin@finants.test")
admin.update!(name: "Dan", role: "admin", password: "password", password_confirmation: "password")

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
