# Cover art for the national championship episode: just the champion, with "NATIONAL CHAMPIONS". No game panels,
# picks or host headshots (see ArtworkGenerator for the weekly cover this replaces). The image call, references and
# multipart upload are inherited; there is no facts-extraction step, since everything it says is the champion's name.
module Podcast
  class ChampionshipArtworkGenerator < ArtworkGenerator
    def initialize(champion:, year:, out_path:, model: nil)
      @champion = champion
      @year = year
      @out_path = out_path
      @model = model
    end

    def call
      prompt = image_prompt
      File.write(out_path.sub(/\.png\z/, "_prompt.txt"), prompt)
      File.binwrite(out_path, Base64.decode64(request_image(prompt)))
      out_path
    end

    private

    def image_prompt(_facts = nil)
      <<~PROMPT
        Create a square podcast episode cover that celebrates a national champion. Image 1 is the show logo ("Rising in
        the Sun Belt", a sunburst over palm trees): reproduce that logo in the top-left corner. Image 2 is an earlier
        cover from the same show: copy ONLY its look, the stadium-at-sunset background with stadium lights and its bold
        brush-lettering style. Do NOT copy its game panels, matchups, spreads, picks, host photos or any of its text.

        The cover shows ONE thing: #{@champion}'s football helmet in the team's real colors and logo, large and centered,
        with falling confetti and a golden national championship trophy beside it. Under or above the helmet, in huge
        brush lettering: "NATIONAL CHAMPIONS". The team name "#{@champion.upcase}" and the year "#{@year}" appear once each,
        in big clear letters. Nothing else: no other teams, no panels, no scores, no spreads, no picks, no people.
        Spell every word and number exactly as written.
      PROMPT
    end
  end
end
