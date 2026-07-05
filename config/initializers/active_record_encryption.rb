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

  if keys_missing.call
    path = Rails.root.join("storage", "encryption.key")

    keys =
      if path.exist?
        YAML.safe_load(path.read, symbolize_names: true)
      else
        generated = {
          "primary_key" => SecureRandom.alphanumeric(32),
          "deterministic_key" => SecureRandom.alphanumeric(32),
          "key_derivation_salt" => SecureRandom.alphanumeric(32)
        }
        path.dirname.mkpath
        # Write to a per-process temp file then hard-link into place. link(2) is atomic and
        # fails if the target exists, so concurrently-booting processes can't clobber each
        # other's keys — the loser just reads the winner's file below.
        tmp = path.dirname.join("encryption.key.#{Process.pid}.tmp")
        tmp.write(generated.to_yaml)
        tmp.chmod(0o600)
        begin
          File.link(tmp.to_s, path.to_s)
        rescue Errno::EEXIST
          # Another process won the race; use its key file.
        ensure
          tmp.delete if tmp.exist?
        end
        YAML.safe_load(path.read, symbolize_names: true)
      end

    enc.primary_key         ||= keys[:primary_key]
    enc.deterministic_key   ||= keys[:deterministic_key]
    enc.key_derivation_salt ||= keys[:key_derivation_salt]
  end
end
