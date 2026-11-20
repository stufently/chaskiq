# frozen_string_literal: true

# Loaded by rspec_gate_r6b.sh with `--require`: one line per example whose
# body ran (after hook), written to $R6B_SENTINEL (default tmp/r6b-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("R6B_SENTINEL", "tmp/r6b-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
