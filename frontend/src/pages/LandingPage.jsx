import { Link } from "react-router-dom";
import Card from "../components/Card";

const featureList = [
  { title: "Depth charts, fast", copy: "Drag players into ordered slots with reserves below the line." },
  { title: "Recruiting clarity", copy: "Tag targets, track signing status, and flag position changes." },
  { title: "Coach-first data", copy: "Highlight key attributes per position and see class balance at a glance." },
];

function LandingPage() {
  return (
    <div className="flex flex-col gap-8">
      <section className="rounded-2xl bg-gradient-to-r from-charcoal to-olive p-8 text-white shadow-card">
        <p className="font-chalk text-lg text-white/80">Fall Saturday energy, coach-only clarity.</p>
        <h1 className="mt-2 font-varsity text-4xl tracking-[0.08em] uppercase">NCAA Team Planner</h1>
        <p className="mt-4 max-w-2xl text-white/85">
          Build position boards, manage recruits, and keep your dynasty roster ready for kickoff.
          Designed for the film room, not the merch shop.
        </p>
        <div className="mt-6 flex gap-3">
          <Link
            to="/teams"
            className="rounded-lg bg-burnt px-4 py-2 text-charcoal font-semibold shadow-card transition hover:-translate-y-0.5"
          >
            View Teams
          </Link>
          <Link
            to="/teams/1/setup"
            className="rounded-lg border border-white/40 px-4 py-2 text-white transition hover:bg-white/10"
          >
            Go to Setup
          </Link>
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        {featureList.map((item) => (
          <Card key={item.title}>
            <div className="p-5">
              <h3 className="font-varsity text-lg tracking-[0.06em] uppercase text-charcoal dark:text-white">
                {item.title}
              </h3>
              <p className="mt-2 text-sm text-textSecondary dark:text-white/70">{item.copy}</p>
            </div>
          </Card>
        ))}
      </section>
    </div>
  );
}

export default LandingPage;
