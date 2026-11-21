# frozen_string_literal: true

# Loaded by rspec_gate_r7b.sh with `--require`: one line per example whose
# body ran (after hook), written to $R7B_SENTINEL (default tmp/r7b-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("R7B_SENTINEL", "tmp/r7b-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
