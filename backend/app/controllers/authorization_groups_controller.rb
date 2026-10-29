class AuthorizationGroupsController < ApplicationController
  before_action :require_authentication
  before_action :verify_csrf, except: [:catalog, :index, :show]
  before_action :require_json, only: [:create, :update, :create_rule, :update_rule]

  rescue_from AuthorizationGroupStore::Forbidden do
    api_error("owner_required", "Somente o titular administra os grupos do escritório.", :forbidden)
  end
  rescue_from AuthorizationGroupStore::NotFound do
    api_error("authorization_group_not_found", "Grupo, regra ou vínculo não encontrado.", :not_found)
  end
  rescue_from AuthorizationGroupStore::InvalidInput do
    api_error("invalid_authorization_group", "Informe um nome válido e regras do catálogo de autorização.", :unprocessable_entity)
  end
  rescue_from AuthorizationGroupStore::Conflict do
    api_error("duplicate_authorization_group", "Já existe um grupo com esse nome ou uma regra igual nesse grupo.", :conflict)
  end
  rescue_from CourtCatalog::Unavailable do
    api_error("court_catalog_unavailable", "Não foi possível consultar os tribunais. Tente novamente.", :service_unavailable)
  end

  def catalog
    render json: { operations: with_groups { AuthorizationGroupStore.catalog } }
  end

  def index
    render json: { groups: with_groups { AuthorizationGroupStore.list_groups } }
  end

  def show
    render json: with_groups { AuthorizationGroupStore.find_group(group_id: params[:id]) }
  end

  def create
    group = with_groups { AuthorizationGroupStore.create_group(name: group_name) }
    render json: group, status: :created
  end

  def update
    group = with_groups { AuthorizationGroupStore.update_group(group_id: params[:id], name: group_name) }
    render json: group
  end

  def destroy
    with_groups do
      require_empty_input
      AuthorizationGroupStore.destroy_group(group_id: params[:id])
    end
    head :no_content
  end

  def create_rule
    group = with_groups { AuthorizationGroupStore.create_rule(group_id: params[:id], input: request.request_parameters) }
    render json: group, status: :created
  end

  def update_rule
    group = with_groups do
      AuthorizationGroupStore.update_rule(group_id: params[:id], rule_id: params[:rule_id], input: request.request_parameters)
    end
    render json: group
  end

  def destroy_rule
    group = with_groups do
      require_empty_input
      AuthorizationGroupStore.destroy_rule(group_id: params[:id], rule_id: params[:rule_id])
    end
    render json: group
  end

  def assign_membership
    group = with_groups do
      require_empty_input
      AuthorizationGroupStore.assign_membership_group(group_id: params[:id], membership_id: params[:membership_id])
    end
    render json: group
  end

  def remove_membership
    group = with_groups do
      require_empty_input
      AuthorizationGroupStore.remove_membership_group(group_id: params[:id], membership_id: params[:membership_id])
    end
    render json: group
  end

  private

  def with_groups(&block)
    DatabaseContext.with_session(session_token, &block)
  end

  def group_name
    input = request.request_parameters
    raise AuthorizationGroupStore::InvalidInput unless input.is_a?(Hash) && input.keys == ["name"]
    input.fetch("name")
  end

  def require_empty_input
    raise AuthorizationGroupStore::InvalidInput unless request.request_parameters.empty?
  end

  def require_json
    return if request.media_type == "application/json"
    api_error("invalid_content_type", "Envie os dados em JSON.", :unsupported_media_type)
  end
end
