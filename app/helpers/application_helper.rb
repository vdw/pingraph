module ApplicationHelper
  # Server-side fallbacks, shown until the local-time Stimulus controller re-renders the
  # value in the viewer's own timezone. They always carry the zone, so even without
  # JavaScript nobody mistakes server time for local time.
  LOCAL_TIME_FORMATS = {
    datetime: "%Y-%m-%d %H:%M:%S %Z",
    long: "%B %-d, %Y, %-I:%M %p %Z",
    short: "%b %-d, %Y, %-I:%M %p %Z",
    time: "%-I:%M %p %Z",
    clock: "%H:%M"
  }.freeze

  # <time> element rendered in the viewer's local timezone (see local_time_controller.js).
  def local_time(time, format: :short)
    return "" if time.nil?

    time = time.in_time_zone
    tag.time(
      time.strftime(LOCAL_TIME_FORMATS.fetch(format)),
      datetime: time.iso8601,
      data: { controller: "local-time", local_time_format_value: format }
    )
  end

  # Data attributes that make local-time write "HH:MM - HH:MM<suffix>" into an attribute
  # (e.g. a tooltip title) of any element.
  def local_time_range_data(start_at, end_at, suffix: "", attribute: "title")
    {
      controller: "local-time",
      local_time_datetime_value: start_at.iso8601,
      local_time_end_value: end_at.iso8601,
      local_time_format_value: :clock,
      local_time_suffix_value: suffix,
      local_time_attribute_value: attribute
    }
  end
end
