class CreateIgpsportConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :igpsport_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :email, null: false
      t.text :password, null: false
      t.text :access_token
      t.datetime :token_expires_at
      t.boolean :enabled, null: false, default: true
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.text :last_sync_error

      t.timestamps
    end
  end
end
