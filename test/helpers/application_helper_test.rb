require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "local_time renders a time element with the zone as fallback" do
    time = Time.utc(2026, 9, 25, 14, 5, 9)

    html = local_time(time, format: :datetime)

    assert_includes html, %(datetime="2026-09-25T14:05:09Z")
    assert_includes html, %(data-controller="local-time")
    assert_includes html, %(data-local-time-format-value="datetime")
    assert_includes html, "2026-09-25 14:05:09 UTC"
  end

  test "local_time handles nil" do
    assert_equal "", local_time(nil)
  end
end
