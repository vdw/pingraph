class AddP0DataIntegrityFixes < ActiveRecord::Migration[8.1]
  def up
    # Deduplicate before adding unique constraint.
    # Keep the host with the most probe results; delete the rest (cascades to probe_results).
    duplicate_groups = Host.select(:group_id, :address, :probe_type)
                           .group(:group_id, :address, :probe_type)
                           .having("COUNT(*) > 1")

    duplicate_groups.each do |dupe|
      hosts = Host.where(group_id: dupe.group_id, address: dupe.address, probe_type: dupe.probe_type)
                  .left_joins(:probe_results)
                  .select("hosts.*, COUNT(probe_results.id) AS result_count")
                  .group("hosts.id")
                  .order("result_count DESC")
                  .to_a

      hosts_to_remove = hosts.drop(1)
      hosts_to_remove.each { |h| Host.find(h.id).destroy }
    end

    add_index :hosts, [ :group_id, :address, :probe_type ],
              name: "index_hosts_on_group_address_probe_type",
              unique: true
  end

  def down
    remove_index :hosts, name: "index_hosts_on_group_address_probe_type"
  end
end
