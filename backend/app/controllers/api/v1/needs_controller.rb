module Api
  module V1
    class NeedsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_position_board
      before_action :set_need, only: %i[update destroy]

      def create
        need = @position_board.needs.build(need_params)
        authorize need
        return render_player_mismatch unless valid_players?(need)

        if need.save
          render json: need, status: :created
        else
          render json: { error: need.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def update
        authorize @need
        return render_player_mismatch unless valid_players?(@need, need_params)

        if @need.update(need_params)
          render json: @need
        else
          render json: { error: @need.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def destroy
        authorize @need
        @need.destroy
        head :no_content
      end

      private

      def set_position_board
        @position_board = policy_scope(PositionBoard).find(params[:position_board_id])
      end

      def set_need
        @need = @position_board.needs.find(params[:id])
      end

      def need_params
        params.require(:need).permit(:replacement_player_id, :departing_player_id, :slot_number, :resolved)
      end

      def valid_players?(need, attrs = {})
        rep_id = attrs[:replacement_player_id] || need.replacement_player_id
        dep_id = attrs[:departing_player_id] || need.departing_player_id
        [rep_id, dep_id].compact.all? { |pid| player_in_team?(pid) }
      end

      def player_in_team?(player_id)
        Player.joins(:team).where(teams: { user_id: current_user.id }).exists?(id: player_id)
      end

      def render_player_mismatch
        render json: { error: "Player not in your team", code: "forbidden" }, status: :forbidden
      end
    end
  end
end
