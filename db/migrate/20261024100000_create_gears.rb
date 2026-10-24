class CreateGears < ActiveRecord::Migration[8.1]
  def change
    create_table :gears do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.string :brand
      t.string :model
      t.datetime :retired_at
      t.timestamps
    end

    # One row per (user, sport) is what makes "a sport has at most one default"
    # hold in the database, not just in a validation.
    create_table :gear_defaults do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :gear, null: false, foreign_key: { on_delete: :cascade }
      t.string :sport, null: false
      t.timestamps
    end
    add_index :gear_defaults, [ :user_id, :sport ], unique: true

    create_table :gear_components do |t|
      t.references :gear, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :nickname
      t.date :installed_on, null: false
      t.integer :service_interval_km, null: false
      t.datetime :retired_at
      t.decimal :final_distance
      t.timestamps
    end

    add_reference :activities, :gear, foreign_key: { on_delete: :nullify }
  end
end
