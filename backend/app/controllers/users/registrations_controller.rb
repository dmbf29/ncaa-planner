module Users
  class RegistrationsController < Devise::RegistrationsController
    respond_to :json

    private

    def respond_with(resource, _opts = {})
      if resource.persisted?
        render json: { user: resource.slice(:id, :email, :name) }, status: :created
      else
        render json: { error: resource.errors.full_messages.to_sentence, code: "unprocessable_entity" },
               status: :unprocessable_entity
      end
    end

    def respond_to_on_destroy
      head :no_content
    end
  end
end
