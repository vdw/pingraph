# The first admin. Set PINGRAPH_ADMIN_EMAIL / PINGRAPH_ADMIN_PASSWORD to choose them up
# front; otherwise the defaults below must be changed at first sign-in.
admin_email = ENV["PINGRAPH_ADMIN_EMAIL"].presence || "admin@pingraph.local"
admin_password = ENV["PINGRAPH_ADMIN_PASSWORD"].presence

admin = User.find_or_create_by!(email_address: admin_email) do |u|
  u.password = admin_password || "pingraph123"
  u.must_change_password = admin_password.nil? && !Rails.env.development?
end

if admin.previously_new_record?
  if admin_password
    puts "Admin user: #{admin.email_address} (password from PINGRAPH_ADMIN_PASSWORD)"
  else
    puts "Admin user: #{admin.email_address} / pingraph123#{' (change it at first sign-in)' if admin.must_change_password?}"
  end
end

# --- Sample Groups & Hosts (development only) ---

if Rails.env.development?
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
end
