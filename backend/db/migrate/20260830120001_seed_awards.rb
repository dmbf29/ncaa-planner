class SeedAwards < ActiveRecord::Migration[8.0]
  class MigrationAward < ActiveRecord::Base
    self.table_name = "awards"
  end

  # recipient_type: "coach" for the coaching/assistant honors, "player" for
  # everything else. sort_order follows the list below so the Award Winners
  # page renders in a familiar order (marquee player awards first, position
  # awards next, coaching awards, then the specialty/scholar honors).
  AWARDS = [
    { name: "Heisman Trophy", recipient_type: "player", description: "College football's most prestigious award, given to the nation's most outstanding player." },
    { name: "Maxwell Award", recipient_type: "player", description: "Awarded by the Maxwell Football Club to the college football player of the year." },
    { name: "Walter Camp Award", recipient_type: "player", description: "Awarded to the national player of the year as selected by FBS coaches and sports information directors." },
    { name: "Bear Bryant COTY Award", recipient_type: "coach", description: "Awarded to the national college football coach of the year." },
    { name: "Davey O'Brien Award", recipient_type: "player", description: "Awarded to the nation's best quarterback." },
    { name: "Chuck Bednarik Award", recipient_type: "player", description: "Awarded to the defensive player of the year in college football." },
    { name: "Bronko Nagurski Trophy", recipient_type: "player", description: "Awarded to the nation's most outstanding defensive player." },
    { name: "Paycom Jim Thorpe Award", recipient_type: "player", description: "Awarded to the nation's best defensive back." },
    { name: "Doak Walker Award", recipient_type: "player", description: "Awarded to the nation's premier running back." },
    { name: "Fred Biletnikoff Award", recipient_type: "player", description: "Awarded to the nation's most outstanding receiver." },
    { name: "Lombardi Award", recipient_type: "player", description: "Awarded to an outstanding college football lineman or linebacker." },
    { name: "Unitas Golden Arm Award", recipient_type: "player", description: "Awarded to the nation's outstanding upperclassman quarterback." },
    { name: "Edge Rusher of the Year", recipient_type: "player", description: "Awarded to the nation's top edge rusher." },
    { name: "Outland Trophy", recipient_type: "player", description: "Awarded to the nation's most outstanding interior lineman." },
    { name: "John Mackey Award", recipient_type: "player", description: "Awarded to the nation's most outstanding tight end." },
    { name: "Broyles Award", recipient_type: "coach", description: "Awarded to the nation's top assistant coach." },
    { name: "Dick Butkus Award", recipient_type: "player", description: "Awarded to the nation's best linebacker." },
    { name: "Rimington Trophy", recipient_type: "player", description: "Awarded to the nation's premier center." },
    { name: "Lou Groza Award", recipient_type: "player", description: "Awarded to the nation's top placekicker." },
    { name: "Ray Guy Award", recipient_type: "player", description: "Awarded to the nation's top punter." },
    { name: "Jet Award", recipient_type: "player", description: "Awarded to the nation's top return specialist." },
    { name: "Shaun Alexander Award", recipient_type: "player", description: "Awarded to the outstanding freshman player in college football." },
    { name: "Paul Hornung Award", recipient_type: "player", description: "Awarded to the most versatile player in college football." },
    { name: "William V. Campbell Award", recipient_type: "player", description: "Awarded to the nation's premier football scholar-athlete." }
  ].freeze

  def up
    AWARDS.each_with_index do |attrs, index|
      MigrationAward.find_or_create_by!(name: attrs[:name]) do |award|
        award.description = attrs[:description]
        award.recipient_type = attrs[:recipient_type]
        award.sort_order = index
      end
    end
  end

  def down
    MigrationAward.where(name: AWARDS.map { |a| a[:name] }).delete_all
  end
end
