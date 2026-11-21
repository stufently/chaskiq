# frozen_string_literal: true

# Loaded by rspec_gate_fxb.sh with `--require`: one line per example whose
# body ran (after hook), written to $FXB_SENTINEL (default tmp/fxb-sentinel.txt). `--dry-run` runs no hooks, so the file stays empty
# and the gates fail.
path = ENV.fetch("FXB_SENTINEL", "tmp/fxb-sentinel.txt")
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
