module Scheduling
  # Turns the team cards read from an opponent-picker recording (tools/capture/read_card_video.py) into colleges.
  # The card prints the school name in capitals ("FLORIDA INTERNATIONAL"), which matches the colleges' names
  # case-insensitively. A ranked team's rank digit is sometimes glued to the front of the name as a stray letter
  # ("SINDIANA"), so a name that matches nothing is retried without its first character and flagged rank-unread. The
  # team is still ranked then; only the number is unknown.
  class OpponentCards
    include CollegeMatching

    def initialize(season)
      @season = season
    end

    def call(raw_cards)
      cards = Array(raw_cards).map { |raw| match(raw) }
      { cards: cards, colleges: colleges_json, unmatched: cards.count { |card| card[:college_id].nil? } }
    end

    private

    def match(raw)
      name = raw["name"].to_s
      college = resolve_college(name)
      rank_unread = raw["rank_unread"]
      if college.nil? && name.length > 3
        college = resolve_college(name[1..])
        rank_unread ||= college.present?
      end

      {
        college_id: college&.id, raw_name: name, rank: raw["rank"], rank_unread: rank_unread && raw["rank"].nil?,
        overall: raw["overall"], offense: raw["offense"], defense: raw["defense"], prestige: raw["prestige"]
      }
    end
  end
end
