require "digest"

# Replaces the generated storage/encryption.key with a new key and re-encrypts every
# encrypted attribute (notification secrets) with it.
#
# Docker images published from 2026-07-05 until the fix in 16752e6 had an encryption.key
# baked in (the build ran the encryption initializer), and Docker copied it into every new
# volume, so those installs share a key anyone can pull from ghcr.io. `db:prepare`, which the
# image runs on every boot, rotates such a key automatically (lib/tasks/pingraph.rake).
#
# Crash-safe in three steps, using Active Record's support for several primary keys (the last
# encrypts, all decrypt):
#   1. the key file becomes [old, new], so everything stays readable whatever happens next;
#   2. every encrypted attribute is re-encrypted with the new key, in one transaction;
#   3. the key file becomes [new].
# A run interrupted after step 1 leaves a list in the file, and the next run finishes it.
# The key derivation salt is kept (it is not secret); the deterministic key encrypts nothing
# and is simply replaced.
class EncryptionKeyRotation
  PATH = Rails.root.join("storage", "encryption.key")

  # SHA-256 of the storage/encryption.key shipped in each affected ghcr.io/vdw/pingraph image
  # (sha-106faa7, sha-89b475e, sha-3995ea8, sha-c128f99, sha-ecd7dc5, sha-61dbd51).
  LEAKED_KEY_DIGESTS = %w[
    88ac0f206e9b90cc83e313478800f65edcefa09b5b5190121ad54db87373bd5d
    3438dfe0b197e05f429bbc3ac3cef5f30c429f631ec582564d8ba1a1d056f41b
    40014bd24f29213c95301daeea98526117b1ea4f6f8843ddaef0a7c5b13902b8
    1881d06e04fba7b73bba39ba1a6e3387bbf28b64a1fe36c63077ba355ccddbaf
    43357126b60e6efec8fc60d78ccb525604c2c2ed54658d81f13387e3e2cae8f6
    aa27ff05a6edb329c3cee0756edaf12f2c3da09ad49d997b20369d58bf47f307
  ].freeze

  class Error < StandardError; end

  def initialize(path: PATH, leaked_digests: LEAKED_KEY_DIGESTS)
    @path = Pathname(path)
    @leaked_digests = leaked_digests
  end

  # The app reads its keys from the file (not ENV or credentials), and the file holds a
  # published key or an interrupted rotation.
  def needed?
    file_in_use? && (leaked? || unfinished?)
  end

  def file_in_use?
    @path.exist? && encryption_config.primary_key == file_keys[:primary_key]
  end

  def leaked?
    @leaked_digests.include?(Digest::SHA256.hexdigest(@path.read))
  end

  def unfinished?
    file_keys[:primary_key].is_a?(Array)
  end

  # Returns the number of records re-encrypted.
  def call
    raise Error, "#{@path} isn't the key in use (keys come from ENV or credentials); rotate those yourself." unless file_in_use?

    keys = file_keys
    old_keys = Array(keys[:primary_key])
    # Resuming: the last key in the list is the new one, from the interrupted run.
    new_key = unfinished? ? old_keys.last : SecureRandom.alphanumeric(32)
    deterministic_key = unfinished? ? keys[:deterministic_key] : SecureRandom.alphanumeric(32)

    write_keys(primary_key: (old_keys | [ new_key ]), deterministic_key: deterministic_key, salt: keys[:key_derivation_salt])
    count = ApplicationRecord.transaction { reencrypt_all }
    write_keys(primary_key: new_key, deterministic_key: deterministic_key, salt: keys[:key_derivation_salt])
    count
  end

  private

  def file_keys
    YAML.safe_load(@path.read, symbolize_names: true)
  end

  def encryption_config
    ActiveRecord::Encryption.config
  end

  # Writes the file, then switches this process to the same keys.
  def write_keys(primary_key:, deterministic_key:, salt:)
    StorageSecret.replace!(@path, {
      "primary_key" => primary_key,
      "deterministic_key" => deterministic_key,
      "key_derivation_salt" => salt
    }.to_yaml)

    encryption_config.primary_key = primary_key
    encryption_config.deterministic_key = deterministic_key
    ActiveRecord::Encryption.reset_default_context
  end

  def reencrypt_all
    Rails.application.eager_load!
    models = ApplicationRecord.descendants.reject(&:abstract_class?).select { |model| model.encrypted_attributes.present? }

    count = 0
    models.each do |model|
      model.find_each do |record|
        # Reads each encrypted attribute (decrypting with any configured key) and writes it
        # back encrypted with the newest one.
        record.encrypt
        count += 1
      end
    end
    count
  end
end
