class ProbeResult < ApplicationRecord
  belongs_to :host

  enum :probe_type, {
    icmp: 0,
    http: 1,
    tcp: 2,
    dns: 3,
    push: 4,
    docker: 5,
    redis: 6
  }, default: :icmp

  validates :recorded_at, presence: true
  validates :packet_loss, presence: true, if: :icmp?

  # metadata is stored as a JSON string (see ProbeService.persist_result!).
  def parsed_metadata
    metadata.present? ? JSON.parse(metadata) : {}
  rescue JSON::ParserError
    {}
  end

  # One line describing a passed TCP, DNS, push, Docker or Redis check.
  def success_summary
    metadata = parsed_metadata
    case probe_type.to_sym
    when :dns then Array(metadata["records"]).first(3).join(", ").presence || "Resolved"
    when :push then metadata["message"].presence || "Push received"
    when :docker then [ metadata["state"]&.capitalize || "Running", metadata["health"] ].compact.join(", ")
    when :redis then "PONG"
    else "Connected"
    end
  end

  scope :downsampled_for_range, ->(start_time, interval_minutes) do
    interval_seconds = interval_minutes.to_i * 60
    bucket_epoch_sql = "(CAST(strftime('%s', recorded_at) AS INTEGER) / #{interval_seconds}) * #{interval_seconds}"

    # Latency aggregates only successful checks (older rows stored time-to-error on failures).
    where("recorded_at >= ?", start_time)
      .select(
        "#{bucket_epoch_sql} AS bucket_epoch, " \
        "AVG(CASE WHEN success THEN latency END) AS latency, " \
        "MIN(CASE WHEN success THEN min_latency END) AS min_latency, " \
        "MAX(CASE WHEN success THEN max_latency END) AS max_latency, " \
        "AVG(CASE WHEN success THEN jitter END) AS jitter, " \
        "MAX(packet_loss) AS packet_loss"
      )
      .group("bucket_epoch")
      .order(Arel.sql("bucket_epoch ASC"))
  end
end
