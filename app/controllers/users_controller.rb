# frozen_string_literal: true
# typed: yes

class UsersController < ApplicationController
  def me
    if current_user.nil?
      render(status: :not_found)
    else
      projects = Project.all.select{ |project|
        project.main_contacts.include?(current_user.osm_name) ||
          project.user_groups.find{ |_id, user_group| user_group.users.include?(current_user.osm_name) }
      }.map(&:id)

      render json: current_user.as_json.merge({
        projects: projects
      })
    end
  end
end
