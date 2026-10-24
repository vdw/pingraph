class AddTelegramNtfyAndWebhookToSettings < ActiveRecord::Migration[8.1]
  def change
    # Secrets (bot token, ntfy topic URL and token, webhook URL) are encrypted, so text columns.
    add_column :settings, :telegram_enabled, :boolean, default: false, null: false
    add_column :settings, :telegram_bot_token, :text
    add_column :settings, :telegram_chat_id, :string

    add_column :settings, :ntfy_enabled, :boolean, default: false, null: false
    add_column :settings, :ntfy_url, :text
    add_column :settings, :ntfy_token, :text

    add_column :settings, :webhook_enabled, :boolean, default: false, null: false
    add_column :settings, :webhook_url, :text
  end
end
