class ChangePositionsToLineStringOnActivity < ActiveRecord::Migration[8.1]
  def change
    change_table :activities, bulk: true do |t|
      t.remove :positions, type: :string
      t.column :path, :geography, geographic: true, srid: 4326, type: :line_string
    end
  end
end
