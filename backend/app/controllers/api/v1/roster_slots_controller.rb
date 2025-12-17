module Api
  module V1
    class RosterSlotsController < BaseController
      before_action :set_position_board
      before_action :set_roster_slot, only: %i[update destroy]

      def create
        roster_slot = @position_board.roster_slots.build(roster_slot_params)
        authorize roster_slot
        return render_player_mismatch unless valid_player_for_team?(roster_slot.player_id)

        if roster_slot.save
          render json: roster_slot, status: :created
        else
          render json: { error: roster_slot.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def update
        authorize @roster_slot
        return render_player_mismatch unless valid_player_for_team?(roster_slot_params[:player_id] || @roster_slot.player_id)

        if @roster_slot.update(roster_slot_params)
          render json: @roster_slot
        else
          render json: { error: @roster_slot.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def destroy
        authorize @roster_slot
        @roster_slot.destroy
        head :no_content
      end

      private

      def set_position_board
        @position_board = policy_scope(PositionBoard).find(params[:position_board_id])
      end

      def set_roster_slot
        @roster_slot = @position_board.roster_slots.find(params[:id])
      end

      def roster_slot_params
        params.require(:roster_slot).permit(:player_id, :slot_number)
      end

      def valid_player_for_team?(player_id)
        return true if player_id.blank?

        Player.joins(:team).where(teams: { user_id: current_user.id }).exists?(id: player_id)
      end

      def render_player_mismatch
        render json: { error: "Player not in your team", code: "forbidden" }, status: :forbidden
      end
    end
  end
end
