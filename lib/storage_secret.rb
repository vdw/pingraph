require "pathname"

# A secret generated once and kept in storage/, the persistent Docker volume, so it survives
# restarts exactly like the SQLite database. Used for keys a self-hosted install has no other
# way to provide (no master key ships in the image).
#
# Required by config/application.rb, before autoloading is set up, so it is excluded from
# autoload_lib there.
module StorageSecret
  # Returns the file's contents, creating it first with the block's value if it is missing.
  def self.fetch(path)
    path = Pathname(path)
    return path.read if path.exist?

    path.dirname.mkpath
    # Write to a per-process temp file then hard-link into place. link(2) is atomic and
    # fails if the target exists, so concurrently-booting processes can't clobber each
    # other's secret: the loser just reads the winner's file below.
    tmp = path.dirname.join("#{path.basename}.#{Process.pid}.tmp")
    tmp.write(yield)
    tmp.chmod(0o600)
    begin
      File.link(tmp.to_s, path.to_s)
    rescue Errno::EEXIST
      # Another process won the race; use its file.
    ensure
      tmp.delete if tmp.exist?
    end
    path.read
  end

  # Replaces the file atomically (rename(2)), for key rotation: readers see the old contents
  # or the new ones, never a partial file.
  def self.replace!(path, contents)
    path = Pathname(path)
    tmp = path.dirname.join("#{path.basename}.#{Process.pid}.tmp")
    tmp.write(contents)
    tmp.chmod(0o600)
    File.rename(tmp.to_s, path.to_s)
  ensure
    tmp.delete if tmp&.exist?
  end

  # Docker builds run assets:precompile with SECRET_KEY_BASE_DUMMY set. Nothing may be
  # generated then: storage/ in the image would be copied into every new volume, giving
  # every install the same, publicly downloadable secret.
  def self.build_time?
    ENV["SECRET_KEY_BASE_DUMMY"].present?
  end
end
