# frozen_string_literal: true

# Seed sample data in development when the DB is empty.
# Runs once after a fresh `db:reset` or `db:setup` so the terminal
# page at `/` shows demo events on first boot.
Rails.application.config.after_initialize do
  next unless Rails.env.development?

  # Quietly skip if the conversation table doesn't exist yet.
  begin
    next unless Conversation.table_exists? && Conversation.none?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    next
  end

  # Use a Rake::Task-style inline seed so we don't need a full
  # Rake invocation.
  begin
    conversation = Conversation.singleton
    next if conversation.events.any?

    position = 1
    turn_position = 1
    current_turn = nil

    Pito::Sample::ChatShell.events.each do |event_data|
      if %w[echo user_message].include?(event_data[:kind])
        current_turn = conversation.turns.create!(
          position: turn_position,
          input_kind: "slash",
          input_text: event_data.dig(:payload, :text).to_s
        )
        turn_position += 1
      end

      conversation.events.create!(
        turn: current_turn,
        position:,
        kind: event_data[:kind],
        payload: event_data[:payload]
      )
      position += 1
    end
  rescue ActiveRecord::StatementInvalid
    # Swallow — edge case during boot.
  end
end
