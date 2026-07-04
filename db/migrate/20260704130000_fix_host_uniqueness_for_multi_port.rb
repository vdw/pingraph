class FixHostUniquenessForMultiPort < ActiveRecord::Migration[8.1]
  def up
    remove_index :hosts, name: "index_hosts_on_group_address_probe_type"

    # ICMP and HTTP are unique by address alone within a group+probe_type —
    # pinging the same IP twice is redundant, and for HTTP the full URL is the address.
    add_index :hosts, [ :group_id, :address, :probe_type ],
              name: "index_hosts_unique_non_tcp",
              unique: true,
              where: "probe_type IN (0, 1)"

    # TCP is unique by address+port — the same host can run SSH on 22,
    # MySQL on 3306, and a web server on 8080 and all deserve separate probes.
    add_index :hosts, [ :group_id, :address, :probe_type, :port ],
              name: "index_hosts_unique_tcp",
              unique: true,
              where: "probe_type = 2"
  end

  def down
    remove_index :hosts, name: "index_hosts_unique_non_tcp"
    remove_index :hosts, name: "index_hosts_unique_tcp"
    add_index :hosts, [ :group_id, :address, :probe_type ],
              name: "index_hosts_on_group_address_probe_type",
              unique: true
  end
end
