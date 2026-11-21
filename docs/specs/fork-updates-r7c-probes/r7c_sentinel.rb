# frozen_string_literal: true

# Loaded by rspec_gate_r7c.sh with `--require`: one line per example whose
# body ran (after hook), written to $R7C_SENTINEL (default tmp/r7c-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("R7C_SENTINEL", "tmp/r7c-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
