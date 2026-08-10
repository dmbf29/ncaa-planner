# Shared college-name resolution for the screenshot extractors — matches
# extracted text against both a college's official name and its
# alternate_name (a shortened/abbreviated form some game screens use, e.g.
# "App St." for "Appalachian State"), so a raw exact match can succeed
# before falling back to the LLM's own nickname/abbreviation knowledge.
module CollegeMatching
  UNMATCHED = "Unmatched".freeze

  private

  # Prefers an exact match on plain extracted text (raw_name) over the
  # enum-constrained field (matched_name) — see the including classes' doc
  # comments for why the enum field alone isn't trustworthy.
  def resolve_college(raw_name, matched_name = nil)
    colleges_by_downcased_name[raw_name.to_s.strip.downcase] ||
      (matched_name.present? && matched_name != UNMATCHED ? colleges_by_matchable_name[matched_name] : nil)
  end

  def colleges
    @colleges ||= College.order(:name).to_a
  end

  # Keyed by both name and alternate_name, so either one resolves straight
  # back to the college.
  def colleges_by_matchable_name
    @colleges_by_matchable_name ||= colleges.each_with_object({}) do |college, hash|
      hash[college.name] = college
      hash[college.alternate_name] = college if college.alternate_name.present?
    end
  end

  def colleges_by_downcased_name
    @colleges_by_downcased_name ||= colleges_by_matchable_name.transform_keys(&:downcase)
  end

  # Enum choices offered to the LLM for its "closest official name" guess —
  # includes alternate names too, so a screenshot showing an abbreviation
  # can match it directly instead of relying on the model to infer the full
  # name from scratch.
  def college_names
    @college_names ||= colleges.flat_map { |college| [ college.name, college.alternate_name ].compact } + [ UNMATCHED ]
  end

  def colleges_json
    colleges.map { |college| { id: college.id, name: college.name } }
  end
end
