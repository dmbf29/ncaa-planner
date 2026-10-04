// Compares the OVR shown in the game to the OVR the importer will compute from the extracted ratings.
// node check_ovr.js out_dir/players.json
global.window = {};
require("./ref/cfb27-position-ovr-calculator.js");
const calc = window.TCCfb27PositionOvrCalculator.calculateCfb27PositionRating;
const { players } = JSON.parse(require("fs").readFileSync(process.argv[2]));
let bad = 0;
for (const p of players) {
  const r = calc(p.csv_position, p.ratings);
  const got = r && (r.overall ?? r.ovr ?? r.rating);
  const diff = got == null ? null : got - p.ovr;
  p.computed_ovr = got; p.ovr_diff = diff;
  if (diff == null || Math.abs(diff) > 1) { bad++; console.log(`${p.raw_name} ${p.csv_position} shown ${p.ovr} computed ${got} ${JSON.stringify(r).slice(0, 80)}`); }
}
console.log(`${players.length} players, ${bad} with computed OVR more than 1 away from the game's`);
