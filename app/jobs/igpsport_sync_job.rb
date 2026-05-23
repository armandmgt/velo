class IgpsportSyncJob < ApplicationJob
  queue_as :default

  # With a connection_id: sync that one connection. Without: sync every enabled
  # connection (the form used by the hourly recurring schedule).
  def perform(connection_id = nil)
    if connection_id
      connection = IgpsportConnection.find_by(id: connection_id)
      return unless connection&.enabled?

      IgpsportSyncService.new(connection).call
    else
      IgpsportConnection.where(enabled: true).find_each do |connection|
        IgpsportSyncService.new(connection).call
      end
    end
  end
end
