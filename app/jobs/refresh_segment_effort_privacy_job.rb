# A rider's hidden portion moved (an address zone or the start/end trim
# changed), so which of their segment efforts give away a location may have too.
class RefreshSegmentEffortPrivacyJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(user)
    user.activities.where(id: SegmentEffort.select(:activity_id)).find_each do |activity|
      SegmentEffort.refresh_privacy(activity)
    end
  end
end
