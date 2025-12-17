class ApplicationController < ActionController::API
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError do
    render json: { error: "Not authorized", code: "forbidden" }, status: :forbidden
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found", code: "not_found" }, status: :not_found
  end

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[name])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name])
  end
end
