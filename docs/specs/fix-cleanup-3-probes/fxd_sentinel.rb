# frozen_string_literal: true

# Loaded by rspec_gate_fxd.sh with `--require`: one line per example whose
# body ran (after hook), written to $FXD_SENTINEL (default tmp/fxd-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("FXD_SENTINEL", "tmp/fxd-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
