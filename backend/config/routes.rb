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
        resources :squads, only: %i[index create update destroy]
        resources :position_boards, only: %i[index create update destroy]
        resources :players, only: %i[index create update destroy]
      end

      resources :position_boards, only: [] do
        resources :roster_slots, only: %i[create update destroy]
      end

      resources :flags, only: %i[index]

      resources :dynasties, only: %i[index] do
        resources :seasons, only: %i[show create] do
          member do
            post :analyze_schedule
            post :commit_schedule
            post :analyze_all_americans
            post :commit_all_americans
          end
        end
      end

      resources :games, only: %i[show] do
        member do
          post :analyze
          post :commit
        end
      end

      resources :weeks, only: [] do
        member do
          post :analyze_top_25_rankings
          post :commit_top_25_rankings
        end
      end

      # Public, unauthenticated broadcast data for third-party consumption (e.g. podcast generation).
      get "dynasties/:dynasty_id/seasons/:season_id/preview", to: "season_broadcasts#preview"
      get "dynasties/:dynasty_id/seasons/:season_id/weeks", to: "season_broadcasts#weeks"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
