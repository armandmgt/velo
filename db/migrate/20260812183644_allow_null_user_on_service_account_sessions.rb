class AllowNullUserOnServiceAccountSessions < ActiveRecord::Migration[8.1]
  def change
    change_column_null :sessions, :user_id, true
  end
end
