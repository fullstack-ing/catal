defmodule <%= @web_namespace %>.Router do
  use <%= @web_namespace %>, :router<%= if @html do %>

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {<%= @web_namespace %>.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end<% end %>

  pipeline :api do
    plug :accepts, ["json"]
  end<%= if @html do %>

  scope "/", <%= @web_namespace %> do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", <%= @web_namespace %> do
  #   pipe_through :api
  # end<% else %>

  scope "/api", <%= @web_namespace %> do
    pipe_through :api
  end<% end %><%= if @mailer do %>

  # Enable <%= [@mailer && "Swoosh mailbox preview"] |> Enum.filter(&(&1)) |> Enum.join(" and ") %> in development
  if Application.compile_env(:<%= @web_app_name %>, :dev_routes) do
    scope "/dev" do<%= if @html do %>
      pipe_through :browser<% else %>
      pipe_through [:fetch_session, :protect_from_forgery]<% end %><%= if @mailer do %>
      forward "/mailbox", Plug.Swoosh.MailboxPreview<% end %>
    end
  end<% end %>
end
