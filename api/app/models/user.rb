# frozen_string_literal: true
# typed: false

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[osm_oauth2]

  def self.from_omniauth(auth)
    puts auth.inspect
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.email = 'none@example.com'
    # user.skip_confirmation!
    user.password = Devise.friendly_token[0, 20]

    user.osm_id = auth.extra.raw_info.id
    user.osm_name = auth.extra.raw_info.display_name
    user.osm_image_url = auth.extra.raw_info.image_url

    user.save!
    user
  end
end
