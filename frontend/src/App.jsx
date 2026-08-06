import { Routes, Route } from "react-router-dom";
import Layout from "./components/Layout";
import LandingPage from "./pages/LandingPage";
import TeamsPage from "./pages/TeamsPage";
import TeamSetupPage from "./pages/TeamSetupPage";
import SquadBoardPage from "./pages/SquadBoardPage";
import LoginPage from "./pages/LoginPage";
import SignupPage from "./pages/SignupPage";
import TeamCreatePage from "./pages/TeamCreatePage";
import GraduatesPage from "./pages/GraduatesPage";
import DynastyDashboardPage from "./pages/DynastyDashboardPage";
import ExportPage from "./pages/ExportPage";
import GameUpdatePage from "./pages/GameUpdatePage";
import DynastyUpdatesPage from "./pages/DynastyUpdatesPage";
import Top25UpdatePage from "./pages/Top25UpdatePage";
import ScheduleUpdatePage from "./pages/ScheduleUpdatePage";
import AllAmericansUpdatePage from "./pages/AllAmericansUpdatePage";
import HeismanUpdatePage from "./pages/HeismanUpdatePage";
import NilSpendUpdatePage from "./pages/NilSpendUpdatePage";
import ConferenceStandingsUpdatePage from "./pages/ConferenceStandingsUpdatePage";

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
        <Route path="/teams/:id/graduates" element={<GraduatesPage />} />
        <Route path="/teams/:id/squads/:squadId" element={<SquadBoardPage />} />
        <Route path="/dynasty" element={<DynastyDashboardPage />} />
        <Route path="/dynasty/export" element={<ExportPage />} />
        <Route path="/dynasty/games/:gameId" element={<GameUpdatePage />} />
        <Route path="/dynasty/updates" element={<DynastyUpdatesPage />} />
        <Route path="/dynasty/updates/top25" element={<Top25UpdatePage />} />
        <Route path="/dynasty/updates/schedule" element={<ScheduleUpdatePage />} />
        <Route path="/dynasty/updates/all-americans" element={<AllAmericansUpdatePage />} />
        <Route path="/dynasty/updates/heisman" element={<HeismanUpdatePage />} />
        <Route path="/dynasty/updates/nil-spend" element={<NilSpendUpdatePage />} />
        <Route path="/dynasty/updates/standings" element={<ConferenceStandingsUpdatePage />} />
      </Routes>
    </Layout>
  );
}

export default App;
