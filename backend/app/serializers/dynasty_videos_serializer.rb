# Every recorded game in a dynasty, newest first, for the public Watch page. The page groups them
# by season and week itself, so this stays a flat list.
class DynastyVideosSerializer
  def initialize(dynasty)
    @dynasty = dynasty
  end

  def as_json
    videos = GameVideo.joins(game: { week: :season }).where(seasons: { dynasty_id: @dynasty.id })
                      .includes(game: [ { week: :season }, :college_game_stats,
                                        { home_college: { logo_attachment: :blob } },
                                        { away_college: { logo_attachment: :blob } } ])
                      .order("seasons.year DESC, weeks.number DESC, game_videos.id DESC")
    { videos: videos.map { |video| video_json(video) } }
  end

  private

  def coached_college_ids
    @coached_college_ids ||= CollegeSeason.where(season_id: @dynasty.seasons.select(:id))
                                          .where.not(coach_id: nil).pluck(:season_id, :college_id).to_set
  end

  def video_json(video)
    game = video.game
    week = game.week
    stats = game.college_game_stats.index_by(&:college_id)
    home_score = stats[game.home_college_id]&.final_score
    away_score = stats[game.away_college_id]&.final_score

    {
      id: video.id,
      provider: video.provider,
      source: video.source,
      title: video.title,
      duration_seconds: video.duration_seconds,
      game_id: game.id,
      time: game.time,
      bowl_name: game.bowl_name,
      cfp_round: game.cfp_round,
      season: { id: week.season_id, year: week.season.year },
      week: { id: week.id, number: week.number, name: week.name },
      home: side_json(game.home_college, week.season_id, home_score),
      away: side_json(game.away_college, week.season_id, away_score)
    }
  end

  include Rails.application.routes.url_helpers

  def side_json(college, season_id, score)
    {
      id: college.id,
      name: college.name,
      logo_url: (rails_blob_path(college.logo, only_path: true) if college.logo.attached?),
      coached_by_us: coached_college_ids.include?([ season_id, college.id ]),
      score: score
    }
  end
end
