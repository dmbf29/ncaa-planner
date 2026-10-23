# Runs one step of the weekly podcast episode (see Podcast::WeeklyRun) in the background: prepare (markdown, art,
# script, fact-check), produce (voices, mix, description), publish or regenerate_art. These take minutes, so the
# Export page polls Podcast::EpisodeStatus for progress. The controller marks the job as started before enqueueing it;
# the job marks it finished or failed. Steps skip work that's already on disk, so a failure can simply be retried.
class PodcastEpisodeJob < ApplicationJob
  queue_as :default

  def perform(season_id:, year:, week_number:, step:, episode: nil, redo_audio: false)
    status = Podcast::EpisodeStatus.new(year: year, week_number: week_number)
    run = Podcast::WeeklyRun.new(year: year, week_number: week_number, season_id: season_id, episode: episode,
                                 live: step == "publish", status: status)
    case step
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
