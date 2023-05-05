# frozen_string_literal: true
# typed: strict

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 20_230_503_081_610) do
  # These are extensions that must be enabled in order to support this database
  enable_extension 'plpgsql'
  enable_extension 'postgis'

  # create_table "spatial_ref_sys", primary_key: "srid", id: :integer, default: nil, force: :cascade do |t|
  #   t.string "auth_name", limit: 256
  #   t.integer "auth_srid"
  #   t.string "srtext", limit: 2048
  #   t.string "proj4text", limit: 2048
  #   t.check_constraint "srid > 0 AND srid <= 998999", name: "spatial_ref_sys_srid_check"
  # end


  create_table :users do |t|
    ## Database authenticatable
    t.string :email,              null: false, default: ''
    t.string :encrypted_password, null: false, default: ''

    ## Recoverable
    t.string   :reset_password_token
    t.datetime :reset_password_sent_at

    ## Rememberable
    t.datetime :remember_created_at

    ## Trackable
    # t.integer  :sign_in_count, default: 0, null: false
    # t.datetime :current_sign_in_at
    # t.datetime :last_sign_in_at
    # t.string   :current_sign_in_ip
    # t.string   :last_sign_in_ip

    ## Confirmable
    # t.string   :confirmation_token
    # t.datetime :confirmed_at
    # t.datetime :confirmation_sent_at
    # t.string   :unconfirmed_email # Only if using reconfirmable

    ## Lockable
    # t.integer  :failed_attempts, default: 0, null: false # Only if lock strategy is :failed_attempts
    # t.string   :unlock_token # Only if unlock strategy is :email or :both
    # t.datetime :locked_at

    t.timestamps null: false

    # Omniauth
    t.string :provider
    t.string :uid

    # OSM
    t.string :osm_id, null: false
    t.string :osm_name, null: false
    t.string :osm_image_url, null: false
  end

  add_index :users, :uid, unique: true
  add_index :users, :reset_password_token, unique: true
  # add_index :users, :confirmation_token,   unique: true
  # add_index :users, :unlock_token,         unique: true
end
