defmodule Slap.Repo.Migrations.AddMessageSearchIndex do
  use Ecto.Migration

  def up do
    execute("""
      CREATE INDEX messages_search_idx
      ON messages
      USING gin(to_tsvector('english', body))
    """)
  end

  def down do
    execute("DROP INDEX messages_search_idx")
  end
end
