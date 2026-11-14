module DynastyRewired
  # The season's recruit pool (Dynasty Rewired's `all_recruits` capture, about 4,100 recruits taken once a
  # season) for searching and for filling in a signed recruit's details. It isn't saved: the parsed pool is
  # cached for a few hours (per server), so a page load doesn't re-download ~1 MB or spend API calls.
  #
  # The API says who a recruit is, not where they signed, so signing is still recorded here (see #match
  # and Api::V1::RecruitPoolsController). A recruit's API position is often "ATH" (undecided); the coach
  # places them after they sign.
  class RecruitPool
    CACHE_TTL = 6.hours

    def initialize(season, client: Client.new)
      @season = season
      @client = client
    end

    def all
      Rails.cache.fetch("dynasty_rewired/recruit_pool/#{@season.year}", expires_in: CACHE_TTL) { load }
    end

    def refresh
      Rails.cache.delete("dynasty_rewired/recruit_pool/#{@season.year}")
      all
    end

    # Filters are exact except `query` (a name fragment, accent- and punctuation-insensitive).
    def search(query: nil, position: nil, stars: nil, state: nil, archetype: nil)
      key = self.class.normalize(query)
      all.select do |recruit|
        (key.blank? || recruit[:search_name].include?(key)) &&
          (position.blank? || recruit[:position] == position) &&
          (stars.blank? || recruit[:stars] == stars.to_i) &&
          (state.blank? || recruit[:state] == state) &&
          (archetype.blank? || recruit[:archetype] == archetype)
      end
    end

    def find(rank)
      all.find { |recruit| recruit[:rank] == rank.to_i }
    end

    # The one recruit a signing-screen row ("G. Cushenberry", state, national rank) refers to, or nil when
    # none or more than one fits. The national rank, when the row has it, settles same-name recruits.
    def match(first_initial:, last_name:, state: nil, national_rank: nil)
      last = self.class.normalize(last_name)
      initial = first_initial.to_s.strip[0].to_s.downcase
      return if last.blank?

      fits = all.select { |r| self.class.normalize(r[:last_name]) == last && (initial.blank? || r[:first_name].to_s.downcase.start_with?(initial)) }
      fits = fits.select { |r| r[:rank] == national_rank.to_i } if fits.many? && national_rank.present?
      fits = fits.select { |r| r[:state] == state } if fits.many? && state.present?
      fits.first if fits.one?
    end

    def self.normalize(text)
      text.to_s.unicode_normalize(:nfkd).downcase.gsub(/[^a-z ]/, "").squeeze(" ").strip
    end

    private

    def load
      capture = @client.recruiting(@season.year).select { |c| c["dataset"] == "all_recruits" }.max_by { |c| c["capturedAt"].to_i }
      Array(capture&.dig("recruits")).map do |recruit|
        first, last = Student.split_full_name(recruit["name"])
        {
          rank: recruit["rank"], name: recruit["name"], first_name: first, last_name: last, search_name: self.class.normalize(recruit["name"]),
          stars: recruit["stars"], position: recruit["position"], state: recruit["state"], hometown: recruit["hometown"],
          height_inches: recruit["height"], weight_lbs: recruit["weight"], state_rank: recruit["stateRank"],
          position_rank: recruit["positionRank"], pipeline: recruit["pipeline"], archetype: recruit["archetype"]
        }
      end
    end
  end
end
