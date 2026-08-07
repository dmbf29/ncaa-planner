Rails.application.routes.draw do
  devise_for :users,
             defaults: { format: :json },
             controllers: {
               sessions: "users/sessions",
               registrations: "users/registrations"
             }

  namespace :api do
    namespace :v1 do
      resources :teams, only: %i[index show create update destroy] do
        member do
          post :import_roster
        end
        resources :squads, only: %i[index create update destroy]
        resources :position_boards, only: %i[index create update destroy]
        resources :players, only: %i[index create update destroy]
      end

      resources :position_boards, only: [] do
        resources :roster_slots, only: %i[create update destroy]
      end

      resources :flags, only: %i[index]

      resources :colleges, only: %i[index]

      resources :dynasties, only: %i[index] do
        resources :seasons, only: %i[show create] do
          member do
            post :analyze_schedule
            post :commit_schedule
            post :analyze_all_americans
            post :commit_all_americans
            post :analyze_nil_spend
            post :commit_nil_spend
            post :analyze_conference_standings
            post :commit_conference_standings
          end
        end
      end

      resources :games, only: %i[show] do
        member do
          post :analyze
          post :analyze_narrative
          post :commit
        end
      end

      resources :weeks, only: [] do
        member do
          post :analyze_top_25_rankings
          post :commit_top_25_rankings
          post :analyze_heisman_candidates
          post :commit_heisman_candidates
        end
      end

      # Public, unauthenticated broadcast data for third-party consumption (e.g. podcast generation).
      get "dynasties/:dynasty_id/seasons/:season_id/preview", to: "season_broadcasts#preview"
      get "dynasties/:dynasty_id/seasons/:season_id/weeks", to: "season_broadcasts#weeks"
      get "dynasties/:dynasty_id/seasons/:season_id/team_breakdown", to: "season_broadcasts#team_breakdown"

      # Public, unauthenticated dashboard data for the shareable dynasty portal — same
      # no-ownership-check reasoning as the broadcast routes above, but shaped for the frontend UI.
      get "dynasties/:id", to: "dynasty_portals#show"
      get "dynasties/:dynasty_id/seasons/:season_id/dashboard", to: "dynasty_portals#dashboard"
      get "dynasties/:dynasty_id/seasons/:season_id/standings", to: "dynasty_portals#standings"
      get "dynasties/:dynasty_id/seasons/:season_id/weeks/:week_number/rankings", to: "dynasty_portals#rankings"
      get "dynasties/:dynasty_id/seasons/:season_id/all_americans", to: "dynasty_portals#all_americans"
      get "dynasties/:dynasty_id/seasons/:season_id/college_seasons/:college_season_id/roster",
          to: "dynasty_portals#roster"
      get "dynasties/:dynasty_id/seasons/:season_id/weeks/:week_number/games", to: "dynasty_portals#week_games"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
