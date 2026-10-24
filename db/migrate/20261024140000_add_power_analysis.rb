class AddPowerAnalysis < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ftp, :integer

    add_column :activities, :normalized_power, :float
    add_column :activities, :power_curve, :jsonb

    add_column :best_efforts, :average_power, :float
    change_column_null :best_efforts, :start_index, true
    change_column_null :best_efforts, :end_index, true
  end
end
