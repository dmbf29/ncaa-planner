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
      </Routes>
    </Layout>
  );
}

export default App;
