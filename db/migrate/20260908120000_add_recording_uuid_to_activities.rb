class AddRecordingUuidToActivities < ActiveRecord::Migration[8.1]
  # Idempotency key for native recordings (#116). The shell mints it at Arrêter
  # and the web review form carries it as a hidden field, so an upload replayed
  # after a kill between the server's 201 and the shell clearing its session
  # resolves to the activity already created instead of duplicating the ride.
  # Null for every other source (manual upload, Strava import, iGPSport sync).
  #
  # Scoped to the owner rather than globally unique: the value arrives in a
  # user-controlled field, and a global index would let one account's upload
  # collide with another's row — a constraint violation on data the uploader
  # can't even see. Scoping matches the lookup, which is scoped for the same
  # reason.
  def change
    add_column :activities, :recording_uuid, :uuid
    add_index :activities, [ :user_id, :recording_uuid ], unique: true
  end
end
