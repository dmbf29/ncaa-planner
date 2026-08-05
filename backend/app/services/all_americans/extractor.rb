module AllAmericans
  # Orchestrates a full "analyze these All-American screenshots" request:
  # classifies every image by which list it belongs to (ImageClassifier),
  # groups same-list images together, then runs RosterExtractor once per
  # group. Returns one "group" per detected (scope, tier, preseason)
  # combination so the frontend can review/edit each list separately,
  # plus the shared college list for the review UI's manual-match dropdowns.
  class Extractor
    def call(images)
      return { groups: [], colleges: colleges_json } if images.blank?

      classifications = ImageClassifier.new.call(images)
      grouped = classifications.group_by { |row| row.values_at(:scope, :tier, :preseason) }

      groups = grouped.map do |(scope, tier, preseason), rows|
        group_images = rows.filter_map { |row| images[row[:index]] }
        {
          national: scope == ImageClassifier::SCOPE_NATIONAL,
          conference: scope == ImageClassifier::SCOPE_NATIONAL ? nil : scope,
          tier: tier,
          preseason: preseason,
          rows: RosterExtractor.new.call(group_images)
        }
      end

      { groups: groups, colleges: colleges_json }
    end

    private

    def colleges_json
      College.order(:name).map { |college| { id: college.id, name: college.name } }
    end
  end
end
