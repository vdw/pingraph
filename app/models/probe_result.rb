class ProbeResult < ApplicationRecord
  belongs_to :host

  enum :probe_type, {
    icmp: 0,
    http: 1,
    tcp: 2
  }, default: :icmp

  validates :recorded_at, presence: true
  validates :packet_loss, presence: true, if: :icmp?

  scope :downsampled_for_range, ->(start_time, interval_minutes) do
    interval_seconds = interval_minutes.to_i * 60
    bucket_epoch_sql = "(CAST(strftime('%s', recorded_at) AS INTEGER) / #{interval_seconds}) * #{interval_seconds}"

    where("recorded_at >= ?", start_time)
      .select(
        "#{bucket_epoch_sql} AS bucket_epoch, " \
        "AVG(latency) AS latency, " \
        "MIN(min_latency) AS min_latency, " \
        "MAX(max_latency) AS max_latency, " \
        "MAX(packet_loss) AS packet_loss"
      )
      .group("bucket_epoch")
      .order(Arel.sql("bucket_epoch ASC"))
  end
end
