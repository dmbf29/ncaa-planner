import Card from "./Card";
import { API_BASE_URL } from "../lib/apiClient";

function ExistingScreenshotsGallery({ screenshots }) {
  if (!screenshots || screenshots.length === 0) return null;

  return (
    <Card>
      <div className="p-5 space-y-3">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
            Uploaded Screenshots
          </h3>
          <p className="text-sm text-textSecondary">Click one to open it full-size.</p>
        </div>
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-5">
          {screenshots.map((screenshot) => (
            <a key={screenshot.id} href={`${API_BASE_URL}${screenshot.url}`} target="_blank" rel="noreferrer">
              <img
                src={`${API_BASE_URL}${screenshot.url}`}
                alt={screenshot.filename}
                className="h-24 w-full rounded-md border border-border object-cover transition hover:opacity-80 dark:border-darkborder"
              />
            </a>
          ))}
        </div>
      </div>
    </Card>
  );
}

export default ExistingScreenshotsGallery;
