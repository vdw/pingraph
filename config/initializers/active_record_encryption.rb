# Provisions Active Record Encryption keys for this self-hosted, single-tenant app.
#
# Resolution order (see local/p0-plan.md §0.1):
#   1. Anything already set in config (e.g. fixed keys in config/environments/test.rb).
#   2. ENV vars — for operators injecting keys from a secret manager (key/DB separation).
#   3. Rails credentials (active_record_encryption.*), read automatically by the framework.
#   4. An auto-generated keyset persisted to storage/encryption.key.
#
# (4) makes clone-and-run "just work" with real encryption: storage/ is the persistent
# Docker volume, so the key survives restarts exactly like the SQLite database. The key
# lives next to the DB, so it protects against a stray copy of the .sqlite3 file, not a
# full-host compromise — an appropriate threat model for a homelab tool.
#
# NEVER replace this with a hardcoded fallback key: that would make secrets effectively
# plaintext and, because support_unencrypted_data is false, would make anything written
# under the fallback undecryptable once real keys are set.
Rails.application.configure do
  enc = config.active_record.encryption

  enc.primary_key         ||= ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence
  enc.deterministic_key   ||= ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence
  enc.key_derivation_salt ||= ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence

  keys_missing = -> { enc.primary_key.blank? || enc.deterministic_key.blank? || enc.key_derivation_salt.blank? }

  if keys_missing.call
    creds = Rails.application.credentials.active_record_encryption
    if creds.present?
      enc.primary_key         ||= creds.primary_key
      enc.deterministic_key   ||= creds.deterministic_key
      enc.key_derivation_salt ||= creds.key_derivation_salt
    end
  end

  if keys_missing.call && !StorageSecret.build_time?
    yaml = StorageSecret.fetch(Rails.root.join("storage", "encryption.key")) do
      {
        "primary_key" => SecureRandom.alphanumeric(32),
        "deterministic_key" => SecureRandom.alphanumeric(32),
        "key_derivation_salt" => SecureRandom.alphanumeric(32)
      }.to_yaml
    end
    keys = YAML.safe_load(yaml, symbolize_names: true)

    enc.primary_key         ||= keys[:primary_key]
    enc.deterministic_key   ||= keys[:deterministic_key]
    enc.key_derivation_salt ||= keys[:key_derivation_salt]
  end
end
