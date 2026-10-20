# Dev/test seed — first household member + starter categories.
# Idempotent, safe to re-run. Login: admin@finants.test / password

admin = User.find_or_initialize_by(email_address: "admin@finants.test")
admin.update!(name: "Dan", role: "admin", password: "password", password_confirmation: "password")

{
  "income" => %w[Salary Interest Dividends Other],
  "expense" => %w[Groceries Eating\ Out Utilities Rent Mortgage\ Interest
                  School Transport Subscriptions Insurance Health Entertainment
                  Travel Household Giving Other]
}.each do |kind, names|
  names.each do |name|
    Category.find_or_create_by!(name:, kind:) { |c| c.active = true }
  end
end
