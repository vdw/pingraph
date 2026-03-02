# Enable WAL (Write-Ahead Logging) mode for SQLite to handle concurrent writes
# from Solid Queue workers without database locking errors.
Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.adapter_name == "SQLite"
    ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
  end
end
