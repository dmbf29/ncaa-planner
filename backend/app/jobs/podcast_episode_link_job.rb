# Edits the Discord announcement of a podcast episode to link the episode itself once Spotify has listed it, which takes a few
# minutes after publishing. Checks again every few minutes; if it never shows up the post keeps its link to the show.
class PodcastEpisodeLinkJob < ApplicationJob
  queue_as :default

  NotListedYet = Class.new(StandardError)

  retry_on NotListedYet, wait: 3.minutes, attempts: 12 do |job, _error|
    Rails.logger.warn("Spotify never listed #{job.arguments.first[:title].inspect}; its Discord post keeps the show link")
  end

  def perform(message_id:, title:, season:, episode:)
    url = Spotify::Episodes.new.url_for(title) or raise NotListedYet
    Discord::PodcastEpisodePost.new(title: title, season: season, episode: episode).link_episode(message_id, url)
  end
end
