# PROTOTYPE (native mixed-tabs spike, #8): throwaway feed for the native activity list.
json.activities @activities do |activity|
  json.id activity.id
  json.name activity.name
  json.sport activity.sport
  json.location activity.location
  json.start_time activity.start_time.iso8601
  json.distance activity.distance&.to_f
  json.duration_seconds activity.duration.to_i
  json.url activity_url(activity)
end
