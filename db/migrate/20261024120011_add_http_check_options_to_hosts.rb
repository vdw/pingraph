class AddHttpCheckOptionsToHosts < ActiveRecord::Migration[8.1]
  def change
    # Used by HTTP and TCP checks (previously a fixed 5 seconds).
    add_column :hosts, :timeout_seconds, :integer, default: 5, null: false

    add_column :hosts, :http_method, :string, default: "GET", null: false
    # Existing hosts keep today's behavior (redirects are not followed); new hosts follow
    # up to 10, like Uptime Kuma.
    add_column :hosts, :max_redirects, :integer, default: 0, null: false
    change_column_default :hosts, :max_redirects, from: 0, to: 10
    add_column :hosts, :keyword, :string
    add_column :hosts, :keyword_invert, :boolean, default: false, null: false
    # Encrypted (they often carry tokens), so text columns.
    add_column :hosts, :request_headers, :text
    add_column :hosts, :request_body, :text
    add_column :hosts, :basic_auth_user, :string
    add_column :hosts, :basic_auth_password, :text

    # Certificate expiry: the latest seen expiry, the warning window (nil = off) and the
    # expiry already alerted about, so each certificate is reported once.
    add_column :hosts, :ssl_expires_at, :datetime
    add_column :hosts, :ssl_expiry_warn_days, :integer, default: 14
    add_column :hosts, :ssl_expiry_notified_for, :datetime
  end
end
