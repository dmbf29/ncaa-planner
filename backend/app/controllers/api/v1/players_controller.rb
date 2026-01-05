module Api
  module V1
    class PlayersController < BaseController
      before_action :set_team
      before_action :set_player, only: %i[update destroy]

      def index
        players = policy_scope(@team.players.includes(:roster_slot, :position_board, :squad))
        players = players.where(position_board_id: params[:position_board_id]) if params[:position_board_id].present?
        players = players.where(squad_id: params[:squad_id]) if params[:squad_id].present?
        players = players.where(status: params[:status]) if params[:status].present?

        render json: players
      end

      def create
        player = @team.players.build(player_params)
        authorize player

        if player.save
          render json: player, status: :created
        else
          render json: { error: player.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def update
        authorize @player
        if @player.update(player_params)
          render json: @player
        else
          render json: { error: @player.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @player
        @player.roster_slot&.destroy
        @player.destroy
        head :no_content
      end

      private

      def set_team
        @team = policy_scope(Team).find(params[:team_id])
      end

      def set_player
        @player = policy_scope(@team.players).find(params[:id])
      end

      def player_params
        permitted = params.require(:player).permit(
          :name,
          :class_year,
          :dev_trait,
          :archetype,
          :status,
          :recruit_status,
          :star_rating,
          :eval_status,
          :overall,
          :notes,
          :pursued,
          :signed,
          :flagged,
          :position_change_needed,
          :squad_id,
          :position_board_id,
          abilities: [],
          tags: [],
          attributes: {},
          attribute_values: {}
        )
        # Only map provided attributes into attribute_values; do not inject a nil key
        # when neither is present, to avoid wiping existing values.
        if permitted.key?(:attribute_values)
          permitted[:attribute_values] = permitted[:attribute_values].presence
        elsif permitted.key?(:attributes)
          permitted[:attribute_values] = permitted.delete(:attributes)
        end
        permitted
      end
    end
  end
end
