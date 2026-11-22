# frozen_string_literal: true

# Record examples from the after hook. A dry run leaves the file empty.
path = "tmp/r10m-sentinel.txt"
File.write(path, "")
RSpec.configure do |config|
  config.after(:each) do |example|
    File.open(path, "a") { |f| f.puts(example.id) }
  end
end
