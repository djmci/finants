# Dev/test seed — first household member. Idempotent, safe to re-run.
# Login: admin@finants.test / password

admin = User.find_or_initialize_by(email_address: "admin@finants.test")
admin.update!(name: "Dan", role: "admin", password: "password", password_confirmation: "password")
