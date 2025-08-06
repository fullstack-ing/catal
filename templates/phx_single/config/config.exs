# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

<%= if @namespaced? || @ecto || @generators do %>
config :<%= @app_name %><%= if @namespaced? do %>,
  namespace: <%= @app_module %><% end %><%= if @ecto do %>,
  ecto_repos: [<%= @app_module %>.Repo]<% end %><%= if @generators do %>,
  generators: <%= inspect @generators %><% end %><% end %>

# Configures the endpoint
config :<%= @app_name %>, <%= @endpoint_module %>,
  url: [host: "localhost"],
  adapter: <%= inspect @web_adapter_module %>,
  render_errors: [
    formats: [<%= if @html do%>html: <%= @web_namespace %>.ErrorHTML, <% end %>json: <%= @web_namespace %>.ErrorJSON],
    layout: false
  ],
  pubsub_server: <%= @app_module %>.PubSub<%= if @mailer do %>

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :<%= @app_name %>, <%= @app_module %>.Mailer, adapter: Swoosh.Adapters.Local<% end %>

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
