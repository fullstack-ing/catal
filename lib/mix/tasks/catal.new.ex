defmodule Mix.Tasks.Catal.New do
  @moduledoc """
  Creates a new Phoenix project.

  It expects the path of the project as an argument.

      $ mix catal.new PATH [--module MODULE] [--app APP]

  A project at the given PATH will be created. The
  application name and module name will be retrieved
  from the path, unless `--module` or `--app` is given.

  ## Options
    * `--app` - the name of the OTP application

    * `--module` - the name of the base module in
      the generated skeleton

    * `--database` - specify the database adapter for Ecto. One of:

        * `postgres` - via https://github.com/elixir-ecto/postgrex
        * `mysql` - via https://github.com/elixir-ecto/myxql
        * `mssql` - via https://github.com/livehelpnow/tds
        * `sqlite3` - via https://github.com/elixir-sqlite/ecto_sqlite3

      Please check the driver docs for more information
      and requirements. Defaults to "postgres".

    * `--adapter` - specify the http adapter. One of:
        * `cowboy` - via https://github.com/elixir-plug/plug_cowboy
        * `bandit` - via https://github.com/mtrudel/bandit

      Please check the adapter docs for more information
      and requirements. Defaults to "bandit".

    * `--no-ecto` - do not generate Ecto files

    * `--no-gettext` - do not generate gettext files

    * `--no-html` - do not generate HTML views

    * `--no-mailer` - do not generate Swoosh mailer files

    * `--binary-id` - use `binary_id` as primary key type in Ecto schemas

    * `--verbose` - use verbose output

    * `-v`, `--version` - prints the Phoenix installer version

  :TODO: I should call out the use of phx.gen but for now lets not worry about it.

  ## Installation

  `mix catal.new` by default prompts you to fetch and install your
  dependencies. You can enable this behaviour by passing the
  `--install` flag or disable it with the `--no-install` flag.

  ## Examples

      $ mix catal.new hello_world

  Is equivalent to:

      $ mix catal.new hello_world --module HelloWorld

  Or without the HTML(useful for APIs):

      $ mix phx.new ~/Workspace/hello_world --no-html

  ## `PHX_NEW_CACHE_DIR`

  In rare cases, it may be useful to copy the build from a previously
  cached build. To do this, set the `PHX_NEW_CACHE_DIR` environment
  variable before running `mix catal.new`. For example, you could generate a
  cache by running:

  ```shell
  mix catal.new mycache --no-install && cd mycache \
    && mix deps.get && mix deps.compile && mix assets.setup \
    && rm -rf assets config lib priv test mix.exs README.md
  ```

  Your cached build directory should contain:

      _build
      deps
      mix.lock

  Then you could run:

  ```shell
  PHX_NEW_CACHE_DIR=/path/to/mycache mix catal.new myapp
  ```

  The entire cache directory will be copied to the new project, replacing
  any existing files where conflicts exist.
  """
  use Mix.Task
  alias Catal.New.{Generator, Project, Single, Web, Ecto}

  @version Mix.Project.config()[:version]
  @shortdoc "Creates a new Phoenix v#{@version} application"

  @switches [
    dev: :boolean,
    ecto: :boolean,
    app: :string,
    module: :string,
    web_module: :string,
    database: :string,
    binary_id: :boolean,
    html: :boolean,
    gettext: :boolean,
    verbose: :boolean,
    install: :boolean,
    prefix: :string,
    mailer: :boolean,
    adapter: :string,
    inside_docker_env: :boolean,
    from_elixir_install: :boolean,
    version_check: :boolean
  ]

  @reserved_app_names ~w(server table)

  @impl true
  def run([version]) when version in ~w(-v --version) do
    Mix.shell().info("Phoenix installer v#{@version}")
  end

  def run(argv) do
    elixir_version_check!()

    {opts, argv} = OptionParser.parse!(argv, strict: @switches)

    version_task =
      if Keyword.get(opts, :version_check, true) do
        get_latest_version("catal_new")
      end

    result =
      case {opts, argv} do
        {_opts, []} ->
          Mix.Tasks.Help.run(["catal.new"])

        {opts, [base_path | _]} ->
          if opts[:umbrella] do
            generate(base_path, Umbrella, :project_path, opts)
          else
            generate(base_path, Single, :base_path, opts)
          end
      end

    if version_task do
      try do
        # if we get anything else than a `Version`, we'll get a MatchError
        # and fail silently
        %Version{} = latest_version = Task.await(version_task, 3_000)
        maybe_warn_outdated(latest_version)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end

    result
  end

  @doc false
  def run(argv, generator, path) do
    elixir_version_check!()

    case OptionParser.parse!(argv, strict: @switches) do
      {_opts, []} -> Mix.Tasks.Help.run(["catal.new"])
      {opts, [base_path | _]} -> generate(base_path, generator, path, opts)
    end
  end

  defp generate(base_path, generator, path, opts) do
    base_path
    |> Project.new(opts)
    |> generator.prepare_project()
    |> Generator.put_binding()
    |> validate_project(path)
    |> generator.generate()
    |> maybe_copy_cached_build(path)
    |> maybe_init_git(path)
    |> maybe_prompt_to_install_deps(generator, path)
  end

  defp validate_project(%Project{opts: opts} = project, path) do
    check_app_name!(project.app, !!opts[:app])
    check_directory_existence!(Map.fetch!(project, path))
    check_module_name_validity!(project.root_mod)
    check_module_name_availability!(project.root_mod)

    project
  end

  defp maybe_prompt_to_install_deps(%Project{} = project, generator, path_key) do
    # we can skip the install deps setup, even with --install, because we already copied deps
    if project.cached_build_path do
      project
    else
      prompt_to_install_deps(project, generator, path_key)
    end
  end

  defp prompt_to_install_deps(%Project{} = project, generator, path_key) do
    path = Map.fetch!(project, path_key)

    install? =
      Keyword.get_lazy(project.opts, :install, fn ->
        Mix.shell().yes?("\nFetch and install dependencies?")
      end)

    cd_step = ["$ cd #{relative_app_path(path)}"]

    maybe_cd(path, fn ->
      mix_step = install_mix(project, install?)

      if mix_step == [] do
        builders = Keyword.fetch!(project.binding, :asset_builders)

        if builders != [] do
          Mix.shell().info([:green, "* running ", :reset, "mix assets.setup"])

          # First compile only builders so we can install in parallel
          # TODO: Once we require Erlang/OTP 28, jason may no longer be required
          cmd(project, "mix deps.compile jason #{Enum.join(builders, " ")}", log: false)
        end

        tasks =
          Enum.map(builders, fn builder ->
            cmd = "mix do loadpaths --no-compile --no-listeners + #{builder}.install"
            Task.async(fn -> cmd(project, cmd, log: false, cd: project.web_path) end)
          end)

        cmd(project, "mix deps.compile")

        Task.await_many(tasks, :infinity)
      end

      print_missing_steps(cd_step ++ mix_step)

      if Project.ecto?(project) do
        print_ecto_info(generator)
      end

      if path_key == :web_path do
        Mix.shell().info("""
        Your web app requires a PubSub server to be running.
        The PubSub server is typically defined in a `mix catal.new.ecto` app.
        If you don't plan to define an Ecto app, you must explicitly start
        the PubSub in your supervision tree as:

            {Phoenix.PubSub, name: #{inspect(project.app_mod)}.PubSub}
        """)
      end

      print_mix_info(generator)
    end)
  end

  defp maybe_cd(path, func), do: path && File.cd!(path, func)

  defp install_mix(project, install?) do
    if install? do
      cmd(project, "mix deps.get")
    else
      ["$ mix deps.get"]
    end
  end

  defp print_missing_steps(steps) do
    Mix.shell().info("""

    We are almost there! The following steps are missing:

        #{Enum.join(steps, "\n    ")}
    """)
  end

  defp print_ecto_info(Web), do: :ok

  defp print_ecto_info(_gen) do
    Mix.shell().info("""
    Then configure your database in config/dev.exs and run:

        $ mix ecto.create
    """)
  end

  defp print_mix_info(Ecto) do
    Mix.shell().info("""
    You can run your app inside IEx (Interactive Elixir) as:

        $ iex -S mix
    """)
  end

  defp print_mix_info(_gen) do
    Mix.shell().info("""
    Start your Phoenix app with:

        $ mix phx.server

    You can also run your app inside IEx (Interactive Elixir) as:

        $ iex -S mix phx.server
    """)
  end

  defp relative_app_path(path) do
    case Path.relative_to_cwd(path) do
      ^path -> Path.basename(path)
      rel -> rel
    end
  end

  ## Helpers

  defp cmd(%Project{} = project, cmd, opts \\ []) do
    {log?, opts} = Keyword.pop(opts, :log, true)

    if log? do
      Mix.shell().info([:green, "* running ", :reset, cmd])
    end

    case Mix.shell().cmd(cmd, opts ++ cmd_opts(project)) do
      0 -> []
      _ -> ["$ #{cmd}"]
    end
  end

  defp cmd_opts(%Project{} = project) do
    if Project.verbose?(project) do
      []
    else
      [quiet: true]
    end
  end

  defp check_app_name!(name, from_app_flag) do
    with :ok <- validate_not_reserved(name),
         :ok <- validate_app_name_format(name, from_app_flag) do
      :ok
    end
  end

  defp validate_not_reserved(name) when name in @reserved_app_names do
    Mix.raise("Application name cannot be #{inspect(name)} as it is reserved")
  end

  defp validate_not_reserved(_name), do: :ok

  defp validate_app_name_format(name, from_app_flag) do
    if name =~ ~r/^[a-z][a-z0-9_]*$/ do
      :ok
    else
      extra =
        if !from_app_flag do
          ". The application name is inferred from the path, if you'd like to " <>
            "explicitly name the application then use the `--app APP` option."
        else
          ""
        end

      Mix.raise(
        "Application name must start with a letter and have only lowercase " <>
          "letters, numbers and underscore, got: #{inspect(name)}" <> extra
      )
    end
  end

  defp check_module_name_validity!(name) do
    unless inspect(name) =~ Regex.recompile!(~r/^[A-Z]\w*(\.[A-Z]\w*)*$/) do
      Mix.raise(
        "Module name must be a valid Elixir alias (for example: Foo.Bar), got: #{inspect(name)}"
      )
    end
  end

  defp check_module_name_availability!(name) do
    [name]
    |> Module.concat()
    |> Module.split()
    |> Enum.reduce([], fn name, acc ->
      mod = Module.concat([Elixir, name | acc])

      if Code.ensure_loaded?(mod) do
        Mix.raise("Module name #{inspect(mod)} is already taken, please choose another name")
      else
        [name | acc]
      end
    end)
  end

  defp check_directory_existence!(path) do
    if File.dir?(path) and
         not Mix.shell().yes?(
           "The directory #{path} already exists. Are you sure you want to continue?"
         ) do
      Mix.raise("Please select another directory for installation.")
    end
  end

  defp elixir_version_check! do
    unless Version.match?(System.version(), "~> 1.15") do
      Mix.raise(
        "Phoenix v#{@version} requires at least Elixir v1.15\n " <>
          "You have #{System.version()}. Please update accordingly"
      )
    end
  end

  defp git_available? do
    case System.find_executable("git") do
      nil -> false
      _path -> true
    end
  end

  defp inside_git_repo?(path) do
    case System.cmd("git", ["status"], cd: path, stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp maybe_init_git(%Project{} = project, path_key) do
    project_path = Map.fetch!(project, path_key)

    if git_available?() and not inside_git_repo?(project_path) do
      Mix.shell().info([:green, "* initializing git repository", :reset])

      case System.cmd("git", ["init"], cd: project_path) do
        {_output, 0} ->
          :ok

        {output, _} ->
          Mix.shell().error("Failed to initialize git repository: #{output}")
      end
    end

    project
  end

  defp maybe_copy_cached_build(%Project{} = project, path_key) do
    project_path = Map.fetch!(project, path_key)

    case System.fetch_env("PHX_NEW_CACHE_DIR") do
      {:ok, cache_dir} ->
        copy_cached_build(%{project_path: project_path, cache_dir: cache_dir})
        %{project | cached_build_path: cache_dir}

      :error ->
        project
    end
  end

  defp copy_cached_build(%{project_path: project_path, cache_dir: cache_dir}) do
    if File.exists?(cache_dir) do
      Mix.shell().info("Copying cached build from #{cache_dir}")
      System.cmd("cp", ["-Rp", Path.join(cache_dir, "."), project_path])
    end
  end

  defp maybe_warn_outdated(latest_version) do
    if Version.compare(@version, latest_version) == :lt do
      Mix.shell().info([
        :yellow,
        "A new version of catal.new is available:",
        :green,
        " v#{latest_version}",
        :reset,
        ".",
        "\n",
        "You are currently running ",
        :red,
        "v#{@version}",
        :reset,
        ".\n",
        "To update, run:\n\n",
        "    $ mix local.catal\n"
      ])
    end
  end

  # we need to parse JSON, so we only check for new versions on Elixir 1.18+
  if Version.match?(System.version(), "~> 1.18") do
    defp get_latest_version(package) do
      Task.async(fn ->
        # ignore any errors to not prevent the generators from running
        # due to any issues while checking the version
        try do
          with {:ok, package} <- get_package(package) do
            versions =
              for release <- package["releases"],
                  version = Version.parse!(release["version"]),
                  # ignore pre-releases like release candidates, etc.
                  version.pre == [] do
                version
              end

            Enum.max(versions, Version)
          end
        rescue
          e -> {:error, e}
        catch
          :exit, _ -> {:error, :exit}
        end
      end)
    end

    defp get_package(name) do
      http_options =
        [
          ssl: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            depth: 2,
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ],
            versions: [:"tlsv1.2", :"tlsv1.3"]
          ]
        ]

      options = [body_format: :binary]

      case :httpc.request(
             :get,
             {~c"https://hex.pm/api/packages/#{name}",
              [{~c"user-agent", ~c"Mix.Tasks.Phx.New/#{@version}"}]},
             http_options,
             options
           ) do
        {:ok, {{_, 200, _}, _headers, body}} ->
          {:ok, JSON.decode!(body)}

        {:ok, {{_, status, _}, _, _}} ->
          {:error, status}

        {:error, reason} ->
          {:error, reason}
      end
    end
  else
    defp get_latest_version(_), do: nil
  end
end
