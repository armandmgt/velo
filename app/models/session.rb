class Session < ApplicationRecord
  include ServiceAccountSession

  # Optional because service accounts authenticate by token and have no person behind them;
  # ServiceAccountSession restores the presence requirement for ordinary sessions.
  belongs_to :user, optional: true
end
