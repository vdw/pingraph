class AddDnsPushDockerOptionsToHosts < ActiveRecord::Migration[8.1]
  def change
    # DNS checks: the resolver to ask (blank = the system's), the record type, and an
    # optional value one of the answers must equal.
    add_column :hosts, :dns_server, :string
    add_column :hosts, :dns_record_type, :string, default: "A", null: false
    add_column :hosts, :dns_expected_value, :string
    # Docker checks: the daemon to ask (blank = the local socket).
    add_column :hosts, :docker_host, :string
    # Push checks: the secret in the push URL and when a push last arrived.
    add_column :hosts, :push_token, :string
    add_column :hosts, :push_received_at, :datetime
    add_index :hosts, :push_token, unique: true
  end
end
