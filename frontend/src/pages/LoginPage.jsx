import { useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { login } from "../lib/apiClient";

function LoginPage() {
  const navigate = useNavigate();
  const [form, setForm] = useState({ email: "", password: "" });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleChange = (e) => {
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      await login(form);
      navigate("/teams");
    } catch (err) {
      setError(err.message || "Login failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-md">
      <PageHeader title="Log In" eyebrow="Access" />
      <Card>
        <form onSubmit={handleSubmit} className="space-y-4 p-6">
          {error && <p className="text-sm text-danger">{error}</p>}
          <div className="space-y-2">
            <label className="text-sm font-medium text-textSecondary">Email</label>
            <input
              type="email"
              name="email"
              required
              value={form.email}
              onChange={handleChange}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm shadow-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            />
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium text-textSecondary">Password</label>
            <input
              type="password"
              name="password"
              required
              value={form.password}
              onChange={handleChange}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm shadow-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-burnt px-4 py-2 text-charcoal font-semibold shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-70"
          >
            {loading ? "Signing in..." : "Log In"}
          </button>
          <p className="text-center text-sm text-textSecondary">
            Need an account?{" "}
            <Link to="/auth/signup" className="font-semibold text-charcoal underline dark:text-white">
              Sign up
            </Link>
          </p>
        </form>
      </Card>
    </div>
  );
}

export default LoginPage;
