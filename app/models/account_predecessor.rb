# Join table: an account can continue from several closed ones —
# e.g. two old loans consolidated into a single refinanced loan —
# or just one, the usual case.
class AccountPredecessor < ApplicationRecord
  belongs_to :account
  belongs_to :predecessor, class_name: "Account"
end
