# frozen_string_literal: true

# Loaded by rspec_gate_r8a.sh with `--require`: one line per example whose
# body ran (after hook), written to $R8A_SENTINEL (default tmp/r8a-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("R8A_SENTINEL", "tmp/r8a-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
