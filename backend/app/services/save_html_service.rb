require "open-uri"

class SaveHtmlService
  attr_reader :filepath, :url

  def initialize(filepath:, url:)
    @filepath = filepath
    @url = url
  end

  def call
    html = URI.parse(url).open

    File.write(filepath, html.read)
  end
end
