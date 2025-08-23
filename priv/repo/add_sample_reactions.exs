alias Slap.Accounts.User
alias Slap.Chat
alias Slap.Chat.Room
alias Slap.Repo

emojis = [
  "😁","😃","🔥","👍","👎","❤️","😘","🤨","👌","👏","✅","😢","☹️",
]

room = Room |> Repo.get_by!(name: "whatever") |> Repo.preload(messages: [:replies])

users = Repo.all(User)

for message <- room.messages do
  num_reactions = :rand.uniform(5) - 1

  if num_reactions > 0 do
    for _ <- (0..num_reactions) do
      Chat.add_reaction(
        Enum.random(emojis),
        message,
        Enum.random(users)
      )
    end
  end

  # Also add reactions to some replies
  for reply <- message.replies do
    if :rand.uniform() < 0.4 do  # 40% chance of reactions on replies
      num_reply_reactions = :rand.uniform(3) - 1

      if num_reply_reactions > 0 do
        for _ <- (0..num_reply_reactions) do
          Chat.add_reaction(
            Enum.random(emojis),
            reply,
            Enum.random(users)
          )
        end
      end
    end
  end
end
