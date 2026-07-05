require "test_helper"

class Public::StatusControllerTest < ActionDispatch::IntegrationTest
  test "index is accessible without authentication and only shows public groups" do
    public_group = groups(:one)
    private_group = groups(:two)

    public_group.update!(is_public: true, status_slug: "core-infra", description: "Core services")
    private_group.update!(is_public: false, status_slug: nil)

    get public_status_url

    assert_response :success
    assert_includes response.body, public_group.name
    assert_not_includes response.body, private_group.name
    assert_not_includes response.body, "Dashboard"
    assert_not_includes response.body, "Sign out"
  end

  test "show is accessible without authentication for public group slug" do
    group = groups(:one)
    group.update!(is_public: true, status_slug: "core-infra")

    get public_status_group_url(group.status_slug)

    assert_response :success
    assert_includes response.body, group.name
  end

  test "show returns not found for private group slug" do
    group = groups(:one)
    group.update_columns(is_public: false, status_slug: "private-group", updated_at: Time.current)

    get public_status_group_url("private-group")

    assert_response :not_found
  end

  test "index renders uptime percentage for a host with probe data" do
    group = groups(:one)
    group.update!(is_public: true, status_slug: "core-infra")
    host = hosts(:one)
    host.probe_results.delete_all
    host.probe_results.create!(probe_type: :tcp, success: true, recorded_at: 10.minutes.ago)

    get public_status_url

    assert_response :success
    assert_includes response.body, "100.0%"
  end

  test "index renders N/A uptime for a host with no probe data" do
    group = groups(:one)
    group.update!(is_public: true, status_slug: "core-infra")
    host = hosts(:one)
    host.probe_results.delete_all

    get public_status_url

    assert_response :success
    assert_includes response.body, "N/A"
  end

  test "layout includes a 60 second meta refresh" do
    group = groups(:one)
    group.update!(is_public: true, status_slug: "core-infra")

    get public_status_url

    assert_response :success
    assert_includes response.body, %(<meta http-equiv="refresh" content="60">)
  end
end
