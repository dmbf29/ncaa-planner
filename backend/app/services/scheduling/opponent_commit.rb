module Scheduling
  # Saves the reviewed cards for one open week of one coached team: they become that week's possible opponents
  # (replacing any earlier recording for the week; the screenshot's suggested opponent is kept), and each card's
  # ratings and prestige are written onto that college's season so they don't have to be entered by hand later.
  class OpponentCommit
    RATING_FIELDS = %i[overall offense defense prestige].freeze

    def initialize(college_season, week)
      @college_season = college_season
      @week = week
    end

    def call(cards)
      cards = Array(cards).map { |card| card.to_h.deep_symbolize_keys }.select { |card| card[:college_id].present? }
      cards = cards.reject { |card| card[:college_id] == @college_season.college_id }.uniq { |card| card[:college_id] }

      ActiveRecord::Base.transaction do
        @college_season.schedule_options.where(week: @week, suggested: false).where.not(opponent_college_id: cards.pluck(:college_id)).destroy_all
        cards.each { |card| save_option(card) }
        update_ratings(cards)
      end
      { options: cards.size }
    end

    private

    def save_option(card)
      option = @college_season.schedule_options.find_or_initialize_by(week: @week, opponent_college_id: card[:college_id])
      option.update!(rank: card[:rank], ranked: card[:rank].present? || card[:rank_unread] == true)
    end

    def update_ratings(cards)
      @college_season.season.college_seasons.where(college_id: cards.pluck(:college_id)).index_by(&:college_id).each do |college_id, college_season|
        card = cards.find { |c| c[:college_id] == college_id }
        updates = card.slice(*RATING_FIELDS).compact
        college_season.update!(updates) if updates.present?
      end
    end
  end
end
