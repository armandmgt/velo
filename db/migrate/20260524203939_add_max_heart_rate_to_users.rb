class AddMaxHeartRateToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :max_heart_rate, :integer
  end
end
