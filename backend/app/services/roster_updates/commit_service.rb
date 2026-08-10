module RosterUpdates
  # Persists a (possibly user-edited) roster batch update for one team: each row
  # either updates an existing player (player_id present) or creates a new one
  # (player_id blank — a row the user chose to keep after review is a row they want
  # applied; removing a row in the review UI already excludes it from this payload,
  # same as NilSpend's remove-row semantics).
  #
  # Each row commits independently and a validation failure is caught and reported as
  # a warning rather than aborting the rest of the batch, mirroring NilSpend::CommitService.
  class CommitService
    # A real class_year means the player is no longer just a recruit/verbal
    # commit — mirrors the mutual-exclusivity rule already enforced in
    # SquadBoardPage's manual "Class" dropdown (picking a class year there
    # clears these same flags).
    STATUS_FLAG_NAMES = %w[recruit commited].freeze

    def initialize(team)
      @team = team
    end

    def call(rows:, missing_player_actions:)
      warnings = []
      warnings.concat(commit_rows(rows))
      warnings.concat(apply_missing_player_actions(missing_player_actions))
      warnings
    end

    private

    def commit_rows(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: symbolized[:name], error: e.message }
      end
    end

    def commit_row(row)
      if row[:player_id].present?
        update_existing_player(row)
      else
        create_new_player(row)
      end
    end

    def update_existing_player(row)
      player = @team.players.find(row[:player_id])
      board_changed = row[:position_board_id].present? && row[:position_board_id] != player.position_board_id

      player.class_year = row[:class_year]
      player.overall = row[:overall]
      player.nil_amount = row[:nil_amount]
      player.position_board_id = row[:position_board_id] if row[:position_board_id].present?
      merge_attribute_values(player, row[:attribute_values])
      player.save!

      # A stale roster_slot on the old board would otherwise leave the player appearing
      # on two boards at once — occupying a slot on the old one and sitting in the new
      # one's unassigned pool — mirroring the same cleanup SquadBoardPage's manual edit
      # already does when a player's board changes.
      player.roster_slot&.destroy if board_changed
      clear_status_flags(player) if row[:class_year].present?
    end

    # player_flags isn't touched by plain assign_attributes/save! above, so this is a
    # separate step rather than something rolled into the update itself.
    def clear_status_flags(player)
      player.player_flags.joins(:flag).where(flags: { name: STATUS_FLAG_NAMES }).destroy_all
    end

    def create_new_player(row)
      player = @team.players.new(
        name: row[:name],
        status: "rostered",
        class_year: row[:class_year],
        overall: row[:overall],
        nil_amount: row[:nil_amount],
        position_board_id: row[:position_board_id]
      )
      merge_attribute_values(player, row[:attribute_values])
      player.save!
    end

    # attribute_values is a plain jsonb column — assigning it outright would wipe any
    # keys the screenshot doesn't cover (e.g. injury/stamina from a scraped import), so
    # the extracted values are merged on top of whatever the player already has.
    def merge_attribute_values(player, new_values)
      return if new_values.blank?

      player.attribute_values = (player.attribute_values || {}).merge(new_values.compact)
    end

    def apply_missing_player_actions(actions)
      Array(actions).filter_map do |action|
        symbolized = action.deep_symbolize_keys
        apply_missing_player_action(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: symbolized[:player_id], error: e.message }
      end
    end

    def apply_missing_player_action(action)
      return if action[:action].blank? || action[:action] == "keep"

      player = @team.players.find(action[:player_id])
      player.update!(status: action[:action])
    end
  end
end
