class AddChronicleToSeasons < ActiveRecord::Migration[8.0]
  # The season's story, written once after the title game (see SeasonChronicle::Writer) and editable by hand. The
  # podcast hosts read it as league history. First paragraph is a short summary; later ones are fuller storylines.
  def change
    add_column :seasons, :chronicle, :text
  end
end
