# Seed an admin user (change email/password before deploying!)
admin = User.find_or_create_by!(email_address: "admin@pingraph.local") do |u|
  u.password = "pingraph123"
end
puts "Admin user: #{admin.email_address} / pingraph123"

# --- Sample Groups & Hosts ---

external = Group.find_or_create_by!(name: "External Services")
internal = Group.find_or_create_by!(name: "Internal Infrastructure")

[
  { name: "Cloudflare DNS",  address: "1.1.1.1",     interval: 60,  group: external },
  { name: "Google DNS",      address: "8.8.8.8",     interval: 60,  group: external },
  { name: "Google",          address: "google.com",  interval: 120, group: external },
  { name: "Gateway",         address: "192.168.1.1", interval: 30,  group: internal }
].each do |attrs|
  Host.find_or_create_by!(name: attrs[:name], group: attrs[:group]) do |h|
    h.address  = attrs[:address]
    h.interval = attrs[:interval]
  end
end

puts "Seeded #{Group.count} groups and #{Host.count} hosts."
