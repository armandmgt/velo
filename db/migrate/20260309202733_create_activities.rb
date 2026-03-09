class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.string :sport, null: false

      t.timestamps
    end
  end
end
