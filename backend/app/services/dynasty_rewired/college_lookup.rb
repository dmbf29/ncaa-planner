module DynastyRewired
  # Dynasty Rewired school name => College, case-insensitive ("UConn" vs our "UCONN"), trying each
  # college's name before any alternate name. Built once per sync so matching a whole season doesn't
  # query the colleges table per game.
  class CollegeLookup
    def initialize
      colleges = College.all.to_a
      @by_name = {}
      colleges.each { |college| @by_name[college.name.to_s.downcase] ||= college }
      colleges.each { |college| @by_name[college.alternate_name.to_s.downcase] ||= college if college.alternate_name.present? }
    end

    def find(name)
      @by_name[name.to_s.downcase]
    end
  end
end
