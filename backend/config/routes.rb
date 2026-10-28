Rails.application.routes.draw do
  get "/auth/google", to: "google_sessions#new"
  get "/auth/google/callback", to: "google_sessions#create"
  get "/api/session", to: "sessions#show", defaults: { format: :json }
  get "/api/onboarding", to: "onboardings#show", defaults: { format: :json }
  post "/api/onboarding", to: "onboardings#create", defaults: { format: :json }
  get "/api/monitorings/lawyer", to: "lawyer_monitorings#show", defaults: { format: :json }
  get "/api/courts", to: "court_catalogs#index", defaults: { format: :json }
  get "/api/monitorings/parties", to: "party_monitorings#index", defaults: { format: :json }
  post "/api/monitorings/parties", to: "party_monitorings#create", defaults: { format: :json }
  get "/api/monitorings/parties/:id", to: "party_monitorings#show", defaults: { format: :json }
  patch "/api/monitorings/parties/:id", to: "party_monitorings#update", defaults: { format: :json }
  get "/api/monitorings/processes", to: "process_monitorings#index", defaults: { format: :json }
  post "/api/monitorings/processes", to: "process_monitorings#create", defaults: { format: :json }
  get "/api/monitorings/processes/:id", to: "process_monitorings#show", defaults: { format: :json }
  patch "/api/monitorings/processes/:id", to: "process_monitorings#update", defaults: { format: :json }
  get "/api/collection-runs", to: "collection_runs#index", defaults: { format: :json }
  get "/api/collection-runs/:id/jobs", to: "collection_runs#jobs", defaults: { format: :json }
end
