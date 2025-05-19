# frozen_string_literal: true
# typed: ignore

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    # See https://github.com/omniauth/omniauth/wiki/FAQ#rails-session-is-clobbered-after-callback-on-developer-strategy
    # skip_before_action :verify_authenticity_token , only: :osm_oauth2

    def osm_oauth2
      # You need to implement the method below in your model (e.g. app/models/user.rb)
      @user = User.from_omniauth(request.env['omniauth.auth'])

      if @user.persisted?
        # sign_in_and_redirect @user, event: :authentication # this will throw if @user is not activated
        sign_in(@user, @user, event: :authentication)
        redirect_to ENV.fetch('OSM_OAUTH2_REDIRECT', nil)
      else
        session['devise.osm_data'] = request.env['omniauth.auth']
        redirect_to new_user_registration_url
      end
    end

    def failure
      redirect_to ENV.fetch('OSM_OAUTH2_REDIRECT', nil)
    end
  end
end
