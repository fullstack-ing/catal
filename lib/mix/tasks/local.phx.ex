defmodule Mix.Tasks.Local.Phx do
  use Mix.Task

  @shortdoc "Updates the Phoenix project generator locally"

  @moduledoc """
  Updates the Catal Phoenix project generator locally.

      $ mix local.catal

  Accepts the same command line options as `archive.install hex catal_new`.
  """

  @impl true
  def run(args) do
    Mix.Task.run("archive.install", ["hex", "catal_new" | args])
  end
end
