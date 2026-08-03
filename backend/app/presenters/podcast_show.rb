# Shared "show bible" for the dynasty podcast — host personas, ground rules,
# opening script, and tone that both Markdown presenters prepend as a
# system-instruction block for the LLM generating the episode. Single-sourced
# here so the branding/hosts only need updating in one place.
module PodcastShow
  HOSTS = [
    {
      name: "Arlis Boardingham",
      style: "Narrative-driven, big-picture, emotional, former college tight end at Bowling Green."
    },
    {
      name: "Ty Simpson",
      style: "Stat-driven, analytical, tactical, expert analyst, former college quarterback at Western Michigan."
    }
  ].freeze

  RULES = [
    "NEVER use video game terminology (call human coaches \"the rivals\", NOT \"users\"). " \
    "Frame everything as real college football with national stakes."
  ].freeze

  TONE = "Energetic, sharp, humorous ESPN-style studio show banter.".freeze

  module_function

  def host_first_names
    HOSTS.map { |host| host[:name].split.first }
  end

  def directive_lines(show_name:)
    lines = []
    lines << "# 🎙️ SHOW DIRECTIVE & SYSTEM INSTRUCTIONS"
    lines << "> **CRITICAL INSTRUCTIONS FOR AUDIO HOSTS (DO NOT READ ALOUD):**"
    lines << "> - **Podcast Name:** \"#{show_name}\""
    HOSTS.each_with_index { |host, index| lines << "> - **Host #{index + 1}:** #{host[:name]} (#{host[:style]})" }
    lines << "> - **Rules:** #{RULES.join(' ')}"
    lines << "> - **Tone:** #{TONE}"
    lines << ""
    lines
  end

  # Scripted first 30 seconds so the hosts self-introduce and say the show
  # name instead of rambling into vague framing, per listener feedback.
  def opening_script_lines(show_name:, framing_hint:)
    narrator, co_host = HOSTS

    lines = []
    lines << "## 🎬 MANDATORY SHOW OPENING (FIRST 30 SECONDS)"
    lines << "> **You MUST start the audio episode following this exact structure:**"
    lines << "> 1. **#{narrator[:name].split.first}:** Opens with a brief, cinematic line setting the stakes for " \
             "#{framing_hint}, then says: *\"Welcome back to #{show_name}, I'm #{narrator[:name]}...\"*"
    lines << "> 2. **#{co_host[:name].split.first}:** Follows up immediately with: *\"...and I'm #{co_host[:name]}.\"*"
    lines << "> 3. Do NOT skip these self-introductions or the show name under any circumstances."
    lines << ""
    lines
  end

  def run_of_show_lines(segments)
    lines = [ "## 📺 TODAY'S BROADCAST RUN-OF-SHOW" ]
    segments.each_with_index { |segment, index| lines << "- **Segment #{index + 1}:** #{segment}" }
    lines << ""
    lines
  end
end
