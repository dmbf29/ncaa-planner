module StringDistance
  module_function


  # True when two names are plausibly the same written two ways: equal once the characters an OCR'd
  # font can't tell apart (I/l/1, O/0) are folded together, or within one edit (two for long names).
  def similar_name?(a, b)
    x = a.to_s.downcase.gsub(/[^a-z0-9|]/, "").gsub(/[l1|]/, "i").tr("0", "o")
    y = b.to_s.downcase.gsub(/[^a-z0-9|]/, "").gsub(/[l1|]/, "i").tr("0", "o")
    return true if x == y

    damerau(x, y) <= (x.length >= 9 && y.length >= 9 ? 2 : 1)
  end

  # An OCR'd name that still contains the tell-tale lookalike garble: digits or a pipe, a stray trailing period, or a
  # "numeral" made of I/l/| that includes a lowercase l ("Ill", "Il", "IlI").
  def garbled_name?(name)
    text = name.to_s
    return true if text.match?(/[0-9|]/)
    return true if text.match?(/\A[a-z]/) # a name never starts lowercase; a lowercase l is a capital I the font can't show
    return true if text.match?(/\.\z/) && !text.match?(/\b(Jr|Sr)\.\z/)

    text.split(/[\s'-]+/).any? { |token| token.match?(/\A[Il|]{2,}\z/) && token.include?("l") }
  end

  # Like levenshtein, but swapping two adjacent characters ("oiho" / "ohio") counts as one edit.
  def damerau(a, b)
    rows = Array.new(a.length + 1) { |i| [ i ] + Array.new(b.length, 0) }
    (0..b.length).each { |j| rows[0][j] = j }
    (1..a.length).each do |i|
      (1..b.length).each do |j|
        cost = a[i - 1] == b[j - 1] ? 0 : 1
        rows[i][j] = [ rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost ].min
        rows[i][j] = [ rows[i][j], rows[i - 2][j - 2] + 1 ].min if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
      end
    end
    rows[a.length][b.length]
  end

  # Number of single-character edits (insert, delete, substitute) to turn a into b.
  def levenshtein(a, b)
    previous = (0..b.length).to_a
    a.each_char.with_index(1) do |ca, i|
      current = [ i ]
      b.each_char.with_index(1) do |cb, j|
        current << [ previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca == cb ? 0 : 1) ].min
      end
      previous = current
    end
    previous.last
  end
end
