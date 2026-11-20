class ChaskiqPluginGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  def start
    template "api.rb.template", "app/services/message_apis/#{file_name}/api.rb"
    return unless yes?("Would you like to add a presenter?")

    template "presenter.rb.template", "app/services/message_apis/#{file_name}/presenter.rb"
  end
end
