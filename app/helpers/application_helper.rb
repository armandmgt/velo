module ApplicationHelper
  def duration_display(duration)
    duration.parts.map do |_key, value|
      value.to_s.rjust(2, "0")
    end.join(":")
  end
end
