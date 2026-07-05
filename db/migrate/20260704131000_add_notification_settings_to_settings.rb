class AddNotificationSettingsToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :base_url, :string

    add_column :settings, :slack_enabled, :boolean, default: false, null: false
    # Encrypted at rest (see Setting#encrypts). Stored as text since ciphertext is an
    # envelope larger than the plaintext webhook URL.
    add_column :settings, :slack_webhook_url, :text

    add_column :settings, :email_enabled, :boolean, default: false, null: false
    add_column :settings, :smtp_address, :string
    add_column :settings, :smtp_port, :integer, default: 587, null: false
    add_column :settings, :smtp_user_name, :string
    add_column :settings, :smtp_password, :text # encrypted at rest
    add_column :settings, :smtp_authentication, :string, default: "plain", null: false
    add_column :settings, :smtp_starttls, :boolean, default: true, null: false
    add_column :settings, :notification_from_email, :string
    add_column :settings, :notification_recipient_email, :string
  end
end
