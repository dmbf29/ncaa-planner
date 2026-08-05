import axios from "axios";
import { keysToCamel, keysToSnake } from "./case";

export const API_BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:3001";

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    "Content-Type": "application/json",
  },
});

const setToken = (token) => {
  if (token) {
    localStorage.setItem("jwt", token);
    window.dispatchEvent(new Event("storage"));
  }
};

const clearToken = () => {
  localStorage.removeItem("jwt");
  window.dispatchEvent(new Event("storage"));
};

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("jwt");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  if (config.data && !(config.data instanceof FormData)) {
    config.data = keysToSnake(config.data);
  }
  return config;
});

api.interceptors.response.use(
  (response) => {
    if (response.data) {
      response.data = keysToCamel(response.data);
    }
    const authHeader = response.headers.authorization;
    if (authHeader?.startsWith("Bearer ")) {
      setToken(authHeader.replace("Bearer ", ""));
    }
    return response;
  },
  (error) => {
    const status = error.response?.status;
    if (status === 401 || status === 403) {
      clearToken();
    }
    const message = error.response?.data?.error || error.message || "Request failed";
    return Promise.reject(new Error(message));
  },
);

export const fetchFlags = () => api.get("/api/v1/flags").then((r) => r.data);

export const fetchTeams = () => api.get("/api/v1/teams").then((r) => r.data);

export const fetchTeam = (id) => api.get(`/api/v1/teams/${id}`).then((r) => r.data);

export const fetchSquadBoards = (teamId, squadId) =>
  api.get(`/api/v1/teams/${teamId}/position_boards`, { params: { squad_id: squadId } }).then((r) => r.data);

export const createTeam = (payload) => api.post("/api/v1/teams", { team: payload }).then((r) => r.data);

export const createPositionBoard = (teamId, payload) =>
  api.post(`/api/v1/teams/${teamId}/position_boards`, { position_board: payload }).then((r) => r.data);

export const updatePositionBoard = (teamId, id, payload) =>
  api.put(`/api/v1/teams/${teamId}/position_boards/${id}`, { position_board: payload }).then((r) => r.data);

export const deletePositionBoard = (teamId, id) =>
  api.delete(`/api/v1/teams/${teamId}/position_boards/${id}`).then((r) => r.data);

export const fetchPlayers = (teamId, params = {}) =>
  api.get(`/api/v1/teams/${teamId}/players`, { params }).then((r) => r.data);

export const createPlayer = (teamId, payload) =>
  api.post(`/api/v1/teams/${teamId}/players`, { player: payload }).then((r) => r.data);

export const updatePlayer = (teamId, id, payload) =>
  api.put(`/api/v1/teams/${teamId}/players/${id}`, { player: payload }).then((r) => r.data);

export const deletePlayer = (teamId, id) =>
  api.delete(`/api/v1/teams/${teamId}/players/${id}`).then((r) => r.data);

export const createRosterSlot = (positionBoardId, payload) =>
  api.post(`/api/v1/position_boards/${positionBoardId}/roster_slots`, { roster_slot: payload }).then((r) => r.data);

export const updateRosterSlot = (positionBoardId, id, payload) =>
  api.put(`/api/v1/position_boards/${positionBoardId}/roster_slots/${id}`, { roster_slot: payload }).then((r) => r.data);

export const deleteRosterSlot = (positionBoardId, id) =>
  api.delete(`/api/v1/position_boards/${positionBoardId}/roster_slots/${id}`).then((r) => r.data);

export const fetchDynasties = () => api.get("/api/v1/dynasties").then((r) => r.data);

export const fetchSeason = (dynastyId, seasonId) =>
  api.get(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}`).then((r) => r.data);

export const createSeason = (dynastyId, payload) =>
  api.post(`/api/v1/dynasties/${dynastyId}/seasons`, { season: payload }).then((r) => r.data);

export const analyzeSchedule = (dynastyId, seasonId, files) => {
  const formData = new FormData();
  files.forEach((file) => formData.append("images[]", file));
  return api
    .post(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}/analyze_schedule`, formData, {
      headers: { "Content-Type": "multipart/form-data" },
    })
    .then((r) => r.data);
};

export const commitSchedule = (dynastyId, seasonId, weekId, rows) =>
  api
    .post(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}/commit_schedule`, { weekId, rows })
    .then((r) => r.data);

export const analyzeAllAmericans = (dynastyId, seasonId, files) => {
  const formData = new FormData();
  files.forEach((file) => formData.append("images[]", file));
  return api
    .post(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}/analyze_all_americans`, formData, {
      headers: { "Content-Type": "multipart/form-data" },
    })
    .then((r) => r.data);
};

export const commitAllAmericans = (dynastyId, seasonId, groups) =>
  api
    .post(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}/commit_all_americans`, { groups })
    .then((r) => r.data);

export const analyzeNilSpend = (dynastyId, seasonId, files) => {
  const formData = new FormData();
  files.forEach((file) => formData.append("images[]", file));
  return api
    .post(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}/analyze_nil_spend`, formData, {
      headers: { "Content-Type": "multipart/form-data" },
    })
    .then((r) => r.data);
};

export const commitNilSpend = (dynastyId, seasonId, rows) =>
  api
    .post(`/api/v1/dynasties/${dynastyId}/seasons/${seasonId}/commit_nil_spend`, { rows })
    .then((r) => r.data);

export const fetchGame = (id) => api.get(`/api/v1/games/${id}`).then((r) => r.data);

export const analyzeGameStats = (id, buckets) => {
  const formData = new FormData();
  buckets.boxScore.forEach((file) => formData.append("box_score_images[]", file));
  buckets.home.forEach((file) => formData.append("home_images[]", file));
  buckets.away.forEach((file) => formData.append("away_images[]", file));
  return api
    .post(`/api/v1/games/${id}/analyze`, formData, { headers: { "Content-Type": "multipart/form-data" } })
    .then((r) => r.data);
};

export const commitGameStats = (id, analysis) =>
  api.post(`/api/v1/games/${id}/commit`, { analysis }).then((r) => r.data);

export const analyzeTop25Rankings = (weekId, files) => {
  const formData = new FormData();
  files.forEach((file) => formData.append("images[]", file));
  return api
    .post(`/api/v1/weeks/${weekId}/analyze_top_25_rankings`, formData, {
      headers: { "Content-Type": "multipart/form-data" },
    })
    .then((r) => r.data);
};

export const commitTop25Rankings = (weekId, rows) =>
  api.post(`/api/v1/weeks/${weekId}/commit_top_25_rankings`, { rows }).then((r) => r.data);

export const analyzeHeismanCandidates = (weekId, files) => {
  const formData = new FormData();
  files.forEach((file) => formData.append("images[]", file));
  return api
    .post(`/api/v1/weeks/${weekId}/analyze_heisman_candidates`, formData, {
      headers: { "Content-Type": "multipart/form-data" },
    })
    .then((r) => r.data);
};

export const commitHeismanCandidates = (weekId, rows) =>
  api.post(`/api/v1/weeks/${weekId}/commit_heisman_candidates`, { rows }).then((r) => r.data);

export const login = ({ email, password }) =>
  api.post("/users/sign_in", { user: { email, password } }).then((r) => r.data);

export const signup = ({ name, email, password, passwordConfirmation }) =>
  api.post("/users", { user: { name, email, password, password_confirmation: passwordConfirmation } }).then((r) => r.data);

export const logout = () => {
  const token = localStorage.getItem("jwt");
  if (!token) return Promise.resolve(clearToken());
  return api.delete("/users/sign_out").finally(() => clearToken());
};

export default api;
