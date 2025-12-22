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
      resources :needs, only: %i[create update destroy]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
