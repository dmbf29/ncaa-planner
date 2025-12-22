module Api
  module V1
    class PositionBoardsController < BaseController
      before_action :set_team
      before_action :set_position_board, only: %i[update destroy]

      def index
        boards = policy_scope(
          @team.position_boards.includes(
            { roster_slots: :player },
            { needs: %i[replacement_player departing_player] }
          )
        )
        render json: boards.as_json(
          include: {
            roster_slots: {
              only: %i[id player_id slot_number],
              include: {
                player: {
                  only: %i[
                    id
                    name
                    class_year
                    dev_trait
                    archetype
                    overall
                    star_rating
                    status
                    position_board_id
                  ]
                }
              }
            },
            needs: {
              only: %i[id replacement_player_id departing_player_id slot_number resolved],
              include: {
                replacement_player: {
                  only: %i[
                    id
                    name
                    class_year
                    dev_trait
                    archetype
                    overall
                    star_rating
                    status
                    position_board_id
                  ]
                },
                departing_player: {
                  only: %i[
                    id
                    name
                    class_year
                    dev_trait
                    archetype
                    overall
                    star_rating
                    status
                    position_board_id
                  ]
                }
              }
            }
          }
        )
      end

      def create
        board = @team.position_boards.build(position_board_params)
        board.squad_id ||= params[:squad_id]
        board.sort_order ||= @team.position_boards.where(squad_id: board.squad_id).maximum(:sort_order).to_i + 1
        authorize board
        if board.save
          render json: board, status: :created
        else
          render json: { error: board.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def update
        authorize @position_board
        if @position_board.update(position_board_params)
          render json: @position_board
        else
          render json: { error: @position_board.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @position_board
        @position_board.destroy
        head :no_content
      end

      private

      def set_team
        @team = policy_scope(Team).find(params[:team_id])
      end

      def set_position_board
        @position_board = policy_scope(@team.position_boards).find(params[:id])
      end

      def position_board_params
        params.require(:position_board).permit(
          :name,
          :slots_count,
          :sort_order,
          :notes,
          :squad_id,
          highlighted_attributes: [],
          target_archetypes: []
        )
      end
    end
  end
end
