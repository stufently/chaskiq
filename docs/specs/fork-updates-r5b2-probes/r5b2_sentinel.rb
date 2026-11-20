# frozen_string_literal: true

# Loaded by rspec_gate_r5b2.sh with `--require`: one line per example whose
# body ran (after hook), written to $R5B2_SENTINEL (default tmp/r5b2-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("R5B2_SENTINEL", "tmp/r5b2-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
