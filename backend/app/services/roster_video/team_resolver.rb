module RosterVideo
  # Maps the team name OCR'd off a roster recording (e.g. "TEXAS ASM") to a College.
  # Exact (normalized) name/alternate name/abbrev first; otherwise a tiny edit
  # distance is tolerated for OCR slips, but only if exactly one college is that
  # close — "Texas" must never resolve to "Texas A&M". Returns nil rather than guess.
  class TeamResolver
    def initialize(colleges = College.all)
      @entries = colleges.flat_map do |college|
        [ college.name, college.alternate_name, college.abbrev ].compact.map { |label| [ self.class.normalize(label), college ] }
      end
    end

    def call(read_name)
      read = self.class.normalize(read_name)
      return nil if read.empty?

      exact = @entries.select { |label, _| label == read }.map(&:last).uniq
      return exact.first if exact.size == 1

      close = @entries.select { |label, _| label.length > 3 && StringDistance.damerau(read, label) <= (label.length >= 12 ? 2 : 1) }.map(&:last).uniq
      close.size == 1 ? close.first : nil
    end

    def self.normalize(name)
      name.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
