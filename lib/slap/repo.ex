defmodule Slap.Repo do
  use Ecto.Repo,
    otp_app: :slap,
    adapter: Ecto.Adapters.Postgres
end
