require "test_helper"

class GroupTest < ActiveSupport::TestCase
  test "generates status slug when public" do
    group = Group.create!(name: "My Public Group", is_public: true)

    assert_equal "my-public-group", group.status_slug
  end

  test "clears status slug when group becomes private" do
    group = groups(:one)
    group.update!(is_public: true, status_slug: "core-infra")

    group.update!(is_public: false)

    assert_nil group.status_slug
  end
end
