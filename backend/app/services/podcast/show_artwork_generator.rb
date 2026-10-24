# Cover art for the season-long shows (win totals, report cards, signing day, ...). Same image call and look as the
# weekly cover (see ArtworkGenerator), but with one panel per coached team instead of one per game: Claude first pulls
# the few on-image facts the show calls for (team name, win total or record) out of the source markdown, and the
# headline is the show's own title.
module Podcast
  class ShowArtworkGenerator < ArtworkGenerator
    def initialize(markdown_path:, spec:, out_path:, model: nil)
      @preview = File.read(markdown_path)
      @spec = spec
      @out_path = out_path
      @model = model
    end

    private

    attr_reader :spec

    def facts_prompt
      <<~PROMPT
        From the document below, write the exact on-image text for a podcast cover with one panel per coached team
        (the teams that have a coach named in the document), in the document's order, in this format and nothing else:

        TEAM 1: <team name as the document writes it>
        FACT: <#{spec.show[:art_facts]}, short, with numerals, e.g. "OVER/UNDER 7.5">

        Use only what the document states. Do not invent a number.
      PROMPT
    end

    def facts_request
      "<source>\n#{@preview}\n</source>\n\nExtract the cover text now. Output only the TEAM blocks."
    end

    # The show logo plus a previous cover to copy the look from: this show's own if there is one, otherwise the
    # latest weekly cover.
    def references
      # PNGs only: the art folder also holds the *_prompt.txt files written next to generated covers, and a
      # case-insensitive filesystem would let "*Midseason*" match those too.
      own = spec.show[:art_reference] && Dir[File.join(Show::ART_DIR, "#{spec.show[:art_reference]}.png")].reject { |path| path == out_path }.max
      latest = Dir[File.join(Show::ART_DIR, "*_bgb.png")].max
      [ Show::COVER_SOURCE, own || latest ].compact.select { |path| File.exist?(path) && path != out_path }
    end

    def image_prompt(facts)
      <<~PROMPT
        Create a square podcast episode cover in the same style as the reference images. Image 1 is the show logo
        ("Rising in the Sun Belt", a sunburst over palm trees): reproduce that logo in the top-left corner. Image 2 is
        an earlier episode cover from the same show: copy its look, with the stadium-at-sunset background, the bold
        brush-lettering headline, the colored panels, and football helmets in each team's real colors. Do not copy
        the old cover's text or numbers; use only the text below.

        Headline (large brush lettering, same placement as before): "#{spec.show[:headline].call(spec.year)}".

        Show one colored panel per team below with that team's helmet in its real colors, the team name, and its fact.
        Spell every word and number exactly as written:

        #{facts}
      PROMPT
    end
  end
end
