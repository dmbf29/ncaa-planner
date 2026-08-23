import { Routes, Route } from "react-router-dom";
import Layout from "./components/Layout";
import LandingPage from "./pages/LandingPage";
import TeamsPage from "./pages/TeamsPage";
import TeamSetupPage from "./pages/TeamSetupPage";
import SquadBoardPage from "./pages/SquadBoardPage";
import LoginPage from "./pages/LoginPage";
import SignupPage from "./pages/SignupPage";
import TeamCreatePage from "./pages/TeamCreatePage";
import RosterBatchUpdatePage from "./pages/RosterBatchUpdatePage";
import GraduatesPage from "./pages/GraduatesPage";
import DynastyDashboardPage from "./pages/DynastyDashboardPage";
import DynastyShowPage from "./pages/DynastyShowPage";
import ConferenceStandingsPage from "./pages/ConferenceStandingsPage";
import Top25Page from "./pages/Top25Page";
import AllAmericansPage from "./pages/AllAmericansPage";
import RosterPage from "./pages/RosterPage";
import WeekResultsPage from "./pages/WeekResultsPage";
import ExportPage from "./pages/ExportPage";
import GameUpdatePage from "./pages/GameUpdatePage";
import DynastyUpdatesPage from "./pages/DynastyUpdatesPage";
import Top25UpdatePage from "./pages/Top25UpdatePage";
import ScheduleUpdatePage from "./pages/ScheduleUpdatePage";
import AllAmericansUpdatePage from "./pages/AllAmericansUpdatePage";
import HeismanUpdatePage from "./pages/HeismanUpdatePage";
import PlayersOfTheWeekUpdatePage from "./pages/PlayersOfTheWeekUpdatePage";
import NilSpendUpdatePage from "./pages/NilSpendUpdatePage";
import ConferenceStandingsUpdatePage from "./pages/ConferenceStandingsUpdatePage";
import TeamStatsUpdatePage from "./pages/TeamStatsUpdatePage";
import TeamScheduleUpdatePage from "./pages/TeamScheduleUpdatePage";
import RecruitingUpdatePage from "./pages/RecruitingUpdatePage";
import SeasonCoachesPage from "./pages/SeasonCoachesPage";
import TeamAttributesPage from "./pages/TeamAttributesPage";

function App() {
  return (
    <Layout>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/auth/login" element={<LoginPage />} />
        <Route path="/auth/signup" element={<SignupPage />} />
        <Route path="/teams/new" element={<TeamCreatePage />} />
        <Route path="/teams" element={<TeamsPage />} />
        <Route path="/teams/:id/setup" element={<TeamSetupPage />} />
        <Route path="/teams/:id/batch-update" element={<RosterBatchUpdatePage />} />
        <Route path="/teams/:id/graduates" element={<GraduatesPage />} />
        <Route path="/teams/:id/squads/:squadId" element={<SquadBoardPage />} />
        <Route path="/dynasty" element={<DynastyDashboardPage />} />
        <Route path="/dynasty/:dynastyId" element={<DynastyShowPage />} />
        <Route path="/dynasty/:dynastyId/seasons/:seasonId" element={<DynastyShowPage />} />
        <Route path="/dynasty/:dynastyId/seasons/:seasonId/standings" element={<ConferenceStandingsPage />} />
        <Route path="/dynasty/:dynastyId/seasons/:seasonId/weeks/:weekNumber/rankings" element={<Top25Page />} />
        <Route path="/dynasty/:dynastyId/seasons/:seasonId/all-americans" element={<AllAmericansPage />} />
        <Route
          path="/dynasty/:dynastyId/seasons/:seasonId/college_seasons/:collegeSeasonId/roster"
          element={<RosterPage />}
        />
        <Route path="/dynasty/:dynastyId/seasons/:seasonId/weeks/:weekNumber/games" element={<WeekResultsPage />} />
        <Route path="/dynasty/export" element={<ExportPage />} />
        <Route path="/dynasty/games/:gameId" element={<GameUpdatePage />} />
        <Route path="/dynasty/updates" element={<DynastyUpdatesPage />} />
        <Route path="/dynasty/updates/top25" element={<Top25UpdatePage />} />
        <Route path="/dynasty/updates/schedule" element={<ScheduleUpdatePage />} />
        <Route path="/dynasty/updates/all-americans" element={<AllAmericansUpdatePage />} />
        <Route path="/dynasty/updates/heisman" element={<HeismanUpdatePage />} />
        <Route path="/dynasty/updates/players-of-the-week" element={<PlayersOfTheWeekUpdatePage />} />
        <Route path="/dynasty/updates/nil-spend" element={<NilSpendUpdatePage />} />
        <Route path="/dynasty/updates/standings" element={<ConferenceStandingsUpdatePage />} />
        <Route path="/dynasty/updates/team-stats" element={<TeamStatsUpdatePage />} />
        <Route path="/dynasty/updates/team-schedule" element={<TeamScheduleUpdatePage />} />
        <Route path="/dynasty/updates/recruiting" element={<RecruitingUpdatePage />} />
        <Route path="/dynasty/updates/season/coaches" element={<SeasonCoachesPage />} />
        <Route path="/dynasty/updates/team-attributes" element={<TeamAttributesPage />} />
      </Routes>
    </Layout>
  );
}

export default App;
