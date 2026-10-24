# Runs one step of a podcast episode (see Podcast::EpisodeRun) in the background: make (prepare + produce in one go),
# prepare (source markdown, art, script, fact-check), produce (voices, mix, description), publish or regenerate_art. These take minutes, so the
# Export page polls Podcast::EpisodeStatus for progress. The controller marks the job as started before enqueueing it;
# the job marks it finished or failed. Steps skip work that's already on disk, so a failure can simply be retried.
class PodcastEpisodeJob < ApplicationJob
  queue_as :default

  def perform(season_id:, year:, slug:, step:, episode: nil, redo_audio: false)
    spec = Podcast::EpisodeSpec.for(year: year, slug: slug, season: Season.find(season_id)) or raise ArgumentError, "unknown episode #{slug.inspect}"
    status = Podcast::EpisodeStatus.new(spec: spec)
    run = Podcast::EpisodeRun.new(spec: spec, season_id: season_id, episode: episode, live: step == "publish", status: status)
    case step
    when "make" then run.make
    when "prepare" then run.prepare
    when "produce" then run.produce(redo_audio: redo_audio)
    when "publish" then run.publish
    when "regenerate_art" then run.regenerate_art
    else raise ArgumentError, "unknown podcast step #{step.inspect}"
    end
    status.finish_job!
  rescue StandardError => e
    Rails.logger.error("PodcastEpisodeJob #{step} failed: #{e.class}: #{e.message}")
    status&.fail_job!("#{e.class}: #{e.message}")
  end
end
