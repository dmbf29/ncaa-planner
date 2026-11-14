require "net/http"

module DynastyRewired
  # Read-only client for the Dynasty Rewired developer API (60 requests/minute, 2,000/day per token).
  # The token is `DYNASTY_REWIRED` in backend/.env; `DYNASTY_REWIRED_LEAGUE` picks the league and
  # may be left out when the token can read exactly one. The API's Cloudflare rejects Ruby/Python's
  # default User-Agent, so one is always set.
  class Client
    class Error < StandardError; end

    BASE = "https://dynastyrewired.com/api/developer/v1".freeze
    BOX_SCORE_PAGE_SIZE = 20
    MAX_RATE_LIMIT_RETRIES = 3

    def initialize(token: ENV["DYNASTY_REWIRED"], league: ENV["DYNASTY_REWIRED_LEAGUE"].presence)
      raise Error, "DYNASTY_REWIRED (the API token) isn't set in backend/.env." if token.blank?

      @token = token
      @league = league
    end

    def league_id
      @league ||= begin
        leagues = get("leagues")["data"]
        raise Error, "The token can read #{leagues.size} leagues; set DYNASTY_REWIRED_LEAGUE to pick one." unless leagues.one?

        leagues.first["id"]
      end
    end

    def schedule(year)
      get("leagues/#{league_id}/seasons/#{year}/schedule")["data"]
    end

    def rankings(year)
      get("leagues/#{league_id}/seasons/#{year}/rankings")["data"]
    end

    # Every box score for the season, following the `next` cursor; each page is a few MB.
    def box_scores(year)
      games = []
      after = nil
      loop do
        params = { limit: BOX_SCORE_PAGE_SIZE }
        params[:after] = after if after
        page = get("leagues/#{league_id}/seasons/#{year}/box-scores", params)["data"]
        games.concat(page["games"])
        after = page["next"]
        break if after.blank?
      end
      games
    end

    # The roster captures (runs) and which schools each one covers: [{ "teamId", "name" }, ...] is under
    # runs[].schools. Use #roster for a school's players.
    def rosters(year)
      get("leagues/#{league_id}/seasons/#{year}/rosters")["data"]
    end

    # One school's players with ratings, from the newest capture that includes it.
    def roster(year, team_id)
      get("leagues/#{league_id}/seasons/#{year}/rosters/#{team_id}")["data"]
    end

    private

    def get(path, params = {}, attempt = 0)
      uri = URI("#{BASE}/#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{@token}", "User-Agent" => "ncaa-planner", "Accept" => "application/json")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(request) }

      case response.code.to_i
      when 200 then JSON.parse(response.body)
      when 429
        raise Error, "Dynasty Rewired rate limit hit; try again in a minute." if attempt >= MAX_RATE_LIMIT_RETRIES

        sleep([ response["Retry-After"].to_i, 1 ].max.clamp(1, 30))
        get(path, params, attempt + 1)
      else
        raise Error, "Dynasty Rewired returned #{response.code}: #{error_message(response)}"
      end
    end

    def error_message(response)
      body = JSON.parse(response.body)
      body.dig("error", "message") || body["error"] || body["message"] || response.message
    rescue JSON::ParserError
      response.message
    end
  end
end
