import { useState } from "react";
import Card from "./Card";
import ScreenshotLightbox from "./ScreenshotLightbox";
import { API_BASE_URL } from "../lib/apiClient";

// Renders one or more labeled groups of already-saved screenshots as small
// thumbnails, clickable into a shared lightbox. `groups` is
// `[{ label, screenshots }]`; groups with no screenshots are skipped.
function ExistingScreenshotsGallery({ groups }) {
  const [lightboxIndex, setLightboxIndex] = useState(null);

  const visibleGroups = (groups || []).filter((group) => group.screenshots?.length > 0);
  const images = visibleGroups.flatMap((group) =>
    group.screenshots.map((screenshot) => ({ src: `${API_BASE_URL}${screenshot.url}`, alt: screenshot.filename })),
  );

  if (visibleGroups.length === 0) return null;

  let offset = 0;

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
            Uploaded Screenshots
          </h3>
          <p className="text-sm text-textSecondary">Click one to open it full-size.</p>
        </div>
        {visibleGroups.map((group) => {
          const groupOffset = offset;
          offset += group.screenshots.length;
          return (
            <div key={group.label} className="space-y-2">
              <p className="text-xs uppercase tracking-wide text-textSecondary">{group.label}</p>
              <div className="flex flex-wrap gap-2">
                {group.screenshots.map((screenshot, index) => (
                  <button
                    key={screenshot.id}
                    type="button"
                    onClick={() => setLightboxIndex(groupOffset + index)}
                    className="h-14 w-14 shrink-0 overflow-hidden rounded-md border border-border transition hover:opacity-80 dark:border-darkborder"
                  >
                    <img
                      src={`${API_BASE_URL}${screenshot.url}`}
                      alt={screenshot.filename}
                      className="h-full w-full object-cover"
                    />
                  </button>
                ))}
              </div>
            </div>
          );
        })}
      </div>
      <ScreenshotLightbox
        images={images}
        index={lightboxIndex}
        onIndexChange={setLightboxIndex}
        onClose={() => setLightboxIndex(null)}
      />
    </Card>
  );
}

export default ExistingScreenshotsGallery;
