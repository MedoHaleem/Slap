defmodule Slap.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SlapWeb.Telemetry,
      Slap.Repo,
      {DNSCluster, query: Application.get_env(:slap, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Slap.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Slap.Finch},
      # Start a worker by calling: Slap.Worker.start_link(arg)
      # {Slap.Worker, arg},
      # Start to serve requests, typically the last entry
      SlapWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Slap.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SlapWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
