alias Slap.Accounts.User
alias Slap.Chat.Message
alias Slap.Chat.Room
alias Slap.Chat
alias Slap.Repo

room = Repo.insert!(%Room{name: "whatever"})
users = Repo.all(User)
now = DateTime.utc_now() |> DateTime.truncate(:second)

messages =
  for _ <- 1..40 do
    %Message{
      user: Enum.random(users),
      room: room,
      body: Faker.Lorem.Shakespeare.king_richard_iii(),
      inserted_at: DateTime.add(now, -:rand.uniform(10 * 24 * 60), :minute)
    }
  end
  |> Enum.sort_by(& &1.inserted_at, &(DateTime.compare(&1, &2) != :gt))

# Insert all messages first
inserted_messages = Enum.map(messages, &Repo.insert!/1)

# Now add replies to create threads
Enum.each(inserted_messages, fn message ->
  # Only add replies to about 30% of messages
  if :rand.uniform() < 0.3 do
    # Add 1-3 replies to selected messages
    num_replies = :rand.uniform(3)

    for _ <- 1..num_replies do
      reply_user = Enum.random(users)
      reply_body = Faker.Lorem.Shakespeare.king_richard_iii()
      # Set reply time slightly after the original message
      reply_time = DateTime.add(message.inserted_at, :rand.uniform(60), :minute)

      # Create reply with custom timestamp
      reply_changeset =
        %Slap.Chat.Reply{message: message, user: reply_user}
        |> Slap.Chat.Reply.changeset(%{body: reply_body})
        |> Ecto.Changeset.put_change(:inserted_at, reply_time)

      Repo.insert!(reply_changeset)
    end
  end
end)
