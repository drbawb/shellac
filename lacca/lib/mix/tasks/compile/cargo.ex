defmodule Mix.Tasks.Compile.Cargo do
  require Logger
  use Mix.Task.Compiler

  def run(args) do
    Logger.info "cargo args => #{inspect args}"


    case System.find_executable("cargo") do
      nil -> _error_missing_cargo()
      cargo_path -> _run_cargo_build(cargo_path)
    end
  end

  def clean() do
    case System.find_executable("cargo") do
      nil -> _error_missing_cargo()
      cargo_path -> _run_cargo_clean(cargo_path)
    end
  end

  defp _error_missing_cargo(), do: {:error, "Could not locate `cargo` build tool on your system PATH."}

  defp _run_cargo_build(path) do
    Logger.info "mix path :: #{inspect Mix.Project.compile_path()}"
    {_cargo_out, cargo_status} = System.cmd(path, ["build", "--release"], [cd: "../resin", stderr_to_stdout: true])
    Logger.info "build (#{cargo_status})"


    File.mkdir_p!("priv/resin/")
    File.cp!("../resin/target/release/resin", "priv/resin/resind")

    Mix.Project.build_structure()
  end


  defp _run_cargo_clean(path) do
    Logger.info "mix path :: #{inspect Mix.Project.compile_path()}"
    {_cargo_out, cargo_status} = System.cmd(path, ["clean"], [cd: "../resin", stderr_to_stdout: true])
    Logger.info "clean (#{cargo_status})"

    :ok
  end
end
