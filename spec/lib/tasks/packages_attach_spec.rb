# frozen_string_literal: true

require "rails_helper"
require "rake"
require "thor"

RSpec.describe "packages:attach rake task" do
  before(:all) do
    Rake::Task.define_task("environment") unless Rake::Task.task_defined?("environment")
    Rails.application.load_tasks unless Rake::Task.task_defined?("packages:attach")
  end

  around do |example|
    original_logger = Rails.logger
    example.run
    Rails.logger = original_logger
  end

  it "calls attach_default_packages on each app" do
    app1 = double("app1")
    app2 = double("app2")
    allow(App).to receive(:find_each).and_yield(app1).and_yield(app2)
    allow(app1).to receive(:attach_default_packages)
    allow(app2).to receive(:attach_default_packages)

    Rake::Task["packages:attach"].reenable
    Rake::Task["packages:attach"].invoke

    expect(app1).to have_received(:attach_default_packages)
    expect(app2).to have_received(:attach_default_packages)
  end
end
