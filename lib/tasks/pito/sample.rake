# frozen_string_literal: true

namespace :pito do
  namespace :sample do
    desc "Seed the database with sample Conversation + Events for demo"
    task seed: :environment do
      conversation = Conversation.singleton

      # Skip if events already exist
      if conversation.events.any?
        puts "Sample events already exist — skipping seed."
        next
      end

      position = 1
      turn_position = 1

      # Each sample event is a hash with kind + payload.
      # We group them into Turns: "echo" or "user_message" starts a new Turn,
      # subsequent events belong to the same Turn until the next Turn-starter.
      current_turn = nil

      Pito::Sample::ChatShell.events.each do |event_data|
        if %w[echo user_message].include?(event_data[:kind])
          # Start a new Turn for this user message / echo
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

      puts "Seeded #{conversation.events.count} sample events across #{conversation.turns.count} turns."
    end
  end
end
