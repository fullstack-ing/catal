defmodule <%= @web_namespace %>.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use <%= @web_namespace %>, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"
  @doc """
  Translates an error message using gettext.
  """<%= if @gettext do %>
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(<%= @web_namespace %>.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(<%= @web_namespace %>.Gettext, "errors", msg, opts)
    end
  end<% else %>
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(<%= @web_namespace %>.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(<%= @web_namespace %>.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end<% end %>

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
