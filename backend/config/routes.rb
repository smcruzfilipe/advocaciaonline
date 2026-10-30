Rails.application.routes.draw do
  get "/auth/google", to: "google_sessions#new"
  get "/auth/google/callback", to: "google_sessions#create"
  get "/api/session", to: "sessions#show", defaults: { format: :json }
  patch "/api/session/membership", to: "sessions#update", defaults: { format: :json }
  delete "/api/session", to: "sessions#destroy", defaults: { format: :json }
  get "/api/team/credentials", to: "team_credentials#index", defaults: { format: :json }
  post "/api/team/credentials", to: "team_credentials#create", defaults: { format: :json }
  patch "/api/team/credentials/:id", to: "team_credentials#update", defaults: { format: :json }
  post "/api/team/credentials/:id/renewal", to: "team_credentials#renew", defaults: { format: :json }
  delete "/api/team/credentials/:id", to: "team_credentials#destroy", defaults: { format: :json }
  post "/api/team/credentials/:id/invitation", to: "team_credentials#reissue", defaults: { format: :json }
  post "/api/team/invitations/accept", to: "team_invitations#create", defaults: { format: :json }
  get "/api/authorization/catalog", to: "authorization_groups#catalog", defaults: { format: :json }
  get "/api/authorization/groups", to: "authorization_groups#index", defaults: { format: :json }
  post "/api/authorization/groups", to: "authorization_groups#create", defaults: { format: :json }
  get "/api/authorization/groups/:id", to: "authorization_groups#show", defaults: { format: :json }
  patch "/api/authorization/groups/:id", to: "authorization_groups#update", defaults: { format: :json }
  delete "/api/authorization/groups/:id", to: "authorization_groups#destroy", defaults: { format: :json }
  post "/api/authorization/groups/:id/rules", to: "authorization_groups#create_rule", defaults: { format: :json }
  patch "/api/authorization/groups/:id/rules/:rule_id", to: "authorization_groups#update_rule", defaults: { format: :json }
  delete "/api/authorization/groups/:id/rules/:rule_id", to: "authorization_groups#destroy_rule", defaults: { format: :json }
  put "/api/authorization/groups/:id/memberships/:membership_id", to: "authorization_groups#assign_membership", defaults: { format: :json }
  delete "/api/authorization/groups/:id/memberships/:membership_id", to: "authorization_groups#remove_membership", defaults: { format: :json }
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
  get "/api/collection-runs/:id/events", to: "escrevente#events", defaults: { format: :json }
  get "/api/collection-runs/:id/execution", to: "escrevente#execution", defaults: { format: :json }
  get "/api/communications", to: "communications#index", defaults: { format: :json }
  get "/api/communications/:id", to: "communications#show", defaults: { format: :json }
  get "/api/dashboard", to: "dashboard#show", defaults: { format: :json }
end
