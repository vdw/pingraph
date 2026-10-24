require "test_helper"

class EncryptionKeyRotationTest < ActiveSupport::TestCase
  WEBHOOK = "https://hooks.slack.com/services/SECRET".freeze

  setup do
    @config = ActiveRecord::Encryption.config
    @original_keys = { primary_key: @config.primary_key, deterministic_key: @config.deterministic_key }
    @dir = Pathname(Dir.mktmpdir("encryption_key_rotation"))
    @path = @dir.join("encryption.key")
    write_key_file(@config.primary_key)

    @setting = Setting.current
    @setting.update!(slack_enabled: true, base_url: "https://pg.test", slack_webhook_url: WEBHOOK, smtp_password: "s3cret")
  end

  teardown do
    use_keys(**@original_keys)
    FileUtils.rm_rf(@dir)
  end

  test "rotates a leaked key: new key file, secrets re-encrypted, old key no longer works" do
    rotation = rotation_for_current_file
    assert rotation.needed?
    old_ciphertext = raw_webhook

    assert_equal Setting.count, rotation.call

    keys = YAML.safe_load(@path.read)
    assert_kind_of String, keys["primary_key"]
    assert_not_equal @original_keys[:primary_key], keys["primary_key"]
    assert_equal @config.key_derivation_salt, keys["key_derivation_salt"]
    assert_equal 0o600, @path.stat.mode & 0o777
    assert_not_equal old_ciphertext, raw_webhook
    assert_not rotation.needed?

    assert_equal WEBHOOK, Setting.find(@setting.id).slack_webhook_url
    assert_equal "s3cret", Setting.find(@setting.id).smtp_password

    use_keys(**@original_keys)
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) { Setting.find(@setting.id).slack_webhook_url }
  end

  test "an unpublished key is left alone" do
    assert_not EncryptionKeyRotation.new(path: @path, leaked_digests: []).needed?
  end

  test "a key file that isn't in use (keys from ENV or credentials) is left alone" do
    write_key_file("some-other-primary-key-000000000")
    rotation = rotation_for_current_file

    assert_not rotation.needed?
    assert_raises(EncryptionKeyRotation::Error) { rotation.call }
  end

  test "finishes a rotation interrupted after the key file was updated" do
    new_key = "interrupted_rotation_new_key_000"
    write_key_file([ @original_keys[:primary_key], new_key ])
    use_keys(primary_key: [ @original_keys[:primary_key], new_key ], deterministic_key: @original_keys[:deterministic_key])
    rotation = EncryptionKeyRotation.new(path: @path, leaked_digests: [])

    assert rotation.needed?
    rotation.call

    assert_equal new_key, YAML.safe_load(@path.read)["primary_key"]
    use_keys(primary_key: new_key, deterministic_key: @original_keys[:deterministic_key])
    assert_equal WEBHOOK, Setting.find(@setting.id).slack_webhook_url
  end

  private

  def rotation_for_current_file
    EncryptionKeyRotation.new(path: @path, leaked_digests: [ Digest::SHA256.hexdigest(@path.read) ])
  end

  def write_key_file(primary_key)
    @path.write({
      "primary_key" => primary_key,
      "deterministic_key" => @config.deterministic_key,
      "key_derivation_salt" => @config.key_derivation_salt
    }.to_yaml)
  end

  def use_keys(primary_key:, deterministic_key:)
    @config.primary_key = primary_key
    @config.deterministic_key = deterministic_key
    ActiveRecord::Encryption.reset_default_context
  end

  def raw_webhook
    Setting.connection.select_value("SELECT slack_webhook_url FROM settings WHERE id = #{@setting.id}")
  end
end
