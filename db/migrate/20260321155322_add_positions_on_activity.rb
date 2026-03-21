class AddPositionsOnActivity < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :positions, :string
  end
end
