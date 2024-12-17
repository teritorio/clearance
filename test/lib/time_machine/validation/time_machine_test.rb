# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'test/unit'
require './lib/time_machine/validation/time_machine'


class TestValidation < Test::Unit::TestCase
  extend T::Sig

  CONFIG_YAML_HEADER = <<~YAML
    title:
      en: España Navarra
      es: España Navarra
    description:
      en: Spain Navarra.
      es: España Navarra.
    # Set your own OSM username, has admin right on all groups.
    main_contacts: [frodrigo]
    # Free keywords to describe the project
    project_tags: [highway]

    # Set a projection relative to the data location. Should be in meter unit.
    # If you don't know the projection, set the corresponding UTM Zone ESRID code from.
    local_srid: 32630

    # Distance between objects to be considered as a LoCha cluster.
    locha_cluster_distance: 100

    # Project title in different languages
    user_groups:
      # Track the OSM tags on an area
      navarra:
        title:
          es: Navarra
        # Use the boundary polygon defined by the corresponding OSM relation id
        polygon: https://polygons.openstreetmap.fr/get_geojson.py?id=349027&params=0.004000-0.001000-0.001000
        # Tags definition in the siblings export directory
        osm_tags: ./export/highway.osm_tags.json
        users: [] # OSM usernames, validation right on this group
  YAML

  sig { void }
  def test_time_machine_deleted
    accept_all_validators = [Validators::All.new(id: 'no_matching_user_groups', osm_tags_matches: Osm::TagsMatches.new([]), action: 'accept')]

    yaml = CONFIG_YAML_HEADER + <<~YAML
      validators:
        deleted:
          action_force: reject
    YAML
    config = Configuration.parse(yaml, './projects/espana_navarra/')

    assert_equal(1, config.user_groups.size)
    assert_not_empty(config.osm_tags_matches.match({ 'highway' => 'primary' }))
    assert_equal(1, config.user_groups.size)

    locha = [
      # deleted
      [1, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.403669953346252, 43.33633041381836], [-1.403606057167053, 43.33631896972656]]}, "tags": {"highway": "primary"}, "created": "2024-04-21T17:40:33", "deleted": false, "members": null, "version": 8, "username": "Sint E7", "group_ids": ["navarra"], "is_change": false, "changesets": null},
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.403606057167053, 43.33631896972656], [-1.403542041778564, 43.336326599121094]]}, "tags": {"highway": "primary"}, "created": "2024-12-12T19:15:06", "deleted": true, "members": null, "version": 9, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets":
          [{"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }
      ]'],
    ].collect{ |id, p|
      Validation.convert_locha_item({
        'locha_id' => -1,
        'objtype' => 'w',
        'id' => id,
        'p' => JSON.parse(p),
      })
    }

    r = Validation.time_machine_locha_propagate_rejection(config, locha, accept_all_validators).to_a
    assert_equal(1, r.size)

    locha_id, matches, validation_result = r[0]
    assert_equal(-1, locha_id)
    assert_equal(1, matches&.size)
    assert_equal('reject', validation_result&.action)
    assert_equal('deleted', validation_result&.diff&.attribs&.dig('deleted', 0)&.validator_id)
  end

  sig { void }
  def test_time_machine_locha_propagate_rejection
    accept_all_validators = [Validators::All.new(id: 'no_matching_user_groups', osm_tags_matches: Osm::TagsMatches.new([]), action: 'accept')]

    yaml = CONFIG_YAML_HEADER + <<~YAML
      validators:
        geom_changes_insignificant:
          instance: Validators::GeomChanges
          dist: 2
          reject: geom_changes_significant
          accept: geom_changes_insignificant
    YAML
    config = Configuration.parse(yaml, './projects/espana_navarra/')

    locha = [
      [1, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.403669953346252, 43.33633041381836], [-1.403606057167053, 43.33631896972656], [-1.403542041778564, 43.336326599121094], [-1.403480052947998, 43.33634567260742], [-1.403431057929993, 43.33638000488281], [-1.403401017189026, 43.33642578125], [-1.40339195728302, 43.33647155761719]]}, "tags": {"lanes": "1", "highway": "primary", "surface": "asphalt", "junction": "roundabout", "cycleway:right": "no"}, "created": "2024-04-21T17:40:33", "deleted": false, "members": null, "version": 8, "username": "Sint E7", "group_ids": ["navarra"], "is_change": false, "changesets": null},
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.403606057167053, 43.33631896972656], [-1.403542041778564, 43.336326599121094], [-1.403480052947998, 43.33634567260742], [-1.403431057929993, 43.33638000488281]]}, "tags": {"lanes": "1", "highway": "primary", "surface": "asphalt", "junction": "roundabout", "cycleway:right": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 9, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [2, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.40344500541687, 43.336082458496094], [-1.403334021568298, 43.335819244384766], [-1.403192043304443, 43.33551788330078], [-1.403077006340027, 43.33530044555664], [-1.402955055236816, 43.335105895996094], [-1.402822971343994, 43.33492660522461], [-1.402464032173157, 43.334449768066406], [-1.402335047721863, 43.334293365478516], [-1.402083992958069, 43.3339729309082], [-1.401836037635803, 43.33366775512695], [-1.401383996009827, 43.333213806152344], [-1.401142954826355, 43.33301544189453], [-1.400832056999206, 43.33277130126953], [-1.400501012802124, 43.332550048828125], [-1.400282025337219, 43.33241653442383], [-1.400043964385986, 43.33228302001953], [-1.39993405342102, 43.33222198486328], [-1.399340987205505, 43.33192825317383], [-1.399042010307312, 43.33179473876953], [-1.398421049118042, 43.33155059814453], [-1.397680997848511, 43.331268310546875]]}, "tags": {"ref": "D 918", "lanes": "2", "highway": "primary", "name:eu": "Kanbo - Donibane Garazi errepidea", "surface": "asphalt", "cycleway:both": "no"}, "created": "2023-05-05T13:27:04", "deleted": false, "members": null, "version": 9, "username": "Vady_Dubovets", "group_ids": ["navarra"], "is_change": false, "changesets": null},
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.40344500541687, 43.336082458496094], [-1.403334021568298, 43.335819244384766], [-1.403192043304443, 43.33551788330078], [-1.403077006340027, 43.33530044555664], [-1.402955055236816, 43.335105895996094], [-1.402822971343994, 43.33492660522461], [-1.402464032173157, 43.334449768066406], [-1.402335047721863, 43.334293365478516], [-1.402083992958069, 43.3339729309082], [-1.401836037635803, 43.33366775512695], [-1.401383996009827, 43.333213806152344], [-1.401142954826355, 43.33301544189453], [-1.400832056999206, 43.33277130126953]]}, "tags": {"ref": "D 918", "lanes": "2", "highway": "primary", "name:eu": "Kanbo - Donibane Garazi errepidea", "surface": "asphalt", "cycleway:both": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 10, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      # Large geom change
      [3, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.40339195728302, 43.33647155761719], [-1.403406977653503, 43.33652114868164], [-1.403442978858948, 43.33656311035156], [-1.403496026992798, 43.33659362792969]]}, "tags": {"lanes": "1", "highway": "primary", "surface": "asphalt", "junction": "roundabout", "cycleway:right": "no"}, "created": "2024-04-21T17:40:33", "deleted": false, "members": null, "version": 1, "username": "Sint E7", "group_ids": ["navarra"], "is_change": false, "changesets": null},
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[0, 0], [-1.403431057929993, 43.33638000488281], [-1.403401017189026, 43.33642578125], [-1.40339195728302, 43.33647155761719], [-1.403406977653503, 43.33652114868164], [-1.403442978858948, 43.33656311035156], [-1.403496026992798, 43.33659362792969]]}, "tags": {"lanes": "1", "highway": "primary", "surface": "asphalt", "junction": "roundabout", "cycleway:right": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 2, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [4, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.400832056999206, 43.33277130126953], [-1.400501012802124, 43.332550048828125], [-1.400282025337219, 43.33241653442383], [-1.400043964385986, 43.33228302001953]]}, "tags": {"ref": "D 918", "lanes": "2", "highway": "primary", "name:eu": "Kanbo - Donibane Garazi errepidea", "surface": "asphalt", "cycleway:both": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 1, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [5, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.400043964385986, 43.33228302001953], [-1.39993405342102, 43.33222198486328]]}, "tags": {"ref": "D 918", "lanes": "2", "highway": "primary", "name:eu": "Kanbo - Donibane Garazi errepidea", "surface": "asphalt", "cycleway:both": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 1, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [6, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.39993405342102, 43.33222198486328], [-1.399340987205505, 43.33192825317383], [-1.399042010307312, 43.33179473876953], [-1.398421049118042, 43.33155059814453], [-1.397680997848511, 43.331268310546875]]}, "tags": {"ref": "D 918", "lanes": "2", "highway": "primary", "name:eu": "Kanbo - Donibane Garazi errepidea", "surface": "asphalt", "cycleway:both": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 1, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [7, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.403669953346252, 43.33633041381836], [-1.403606057167053, 43.33631896972656]]}, "tags": {"lanes": "1", "highway": "primary", "surface": "asphalt", "junction": "roundabout", "cycleway:right": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 1, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [8, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.400043964385986, 43.33228302001953], [-1.400138020515442, 43.332218170166016], [-1.400166034698486, 43.332191467285156], [-1.400182008743286, 43.33216857910156], [-1.400187015533447, 43.33214569091797], [-1.400190949440002, 43.332115173339844], [-1.400166034698486, 43.33207702636719], [-1.400143027305603, 43.332054138183594], [-1.400117039680481, 43.332035064697266], [-1.39993405342102, 43.33222198486328]]}, "tags": {"oneway": "yes", "highway": "primary_link", "surface": "asphalt", "cycleway:right": "no"}, "created": "2022-10-06T21:05:12", "deleted": false, "members": null, "version": 5, "username": "sorgin Informatique", "group_ids": ["navarra"], "is_change": false, "changesets": null},
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.400043964385986, 43.33228302001953], [-1.400138020515442, 43.332218170166016], [-1.400166034698486, 43.332191467285156], [-1.400182008743286, 43.33216857910156], [-1.400187015533447, 43.33214569091797], [-1.400190949440002, 43.332115173339844]]}, "tags": {"oneway": "yes", "highway": "primary_link", "surface": "asphalt", "cycleway:right": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 6, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
      [9, '[
        {"geom": {"crs": {"type": "name", "properties": {"name": "EPSG:4326"}}, "type": "LineString", "coordinates": [[-1.400190949440002, 43.332115173339844], [-1.400166034698486, 43.33207702636719], [-1.400143027305603, 43.332054138183594], [-1.400117039680481, 43.332035064697266], [-1.39993405342102, 43.33222198486328]]}, "tags": {"oneway": "yes", "highway": "primary_link", "surface": "asphalt", "cycleway:right": "no"}, "created": "2024-12-12T19:15:06", "deleted": false, "members": null, "version": 1, "username": "Sint E7", "group_ids": ["navarra"], "is_change": true, "changesets": [
          {"id": 160220548, "uid": 146393, "open": false, "user": "Sint E7", "maxlat": 43.495373, "maxlon": -1.0331469, "minlat": 43.071014, "minlon": -1.4963601, "closed_at": "2024-12-12T19:15:08", "created_at": "2024-12-12T19:15:06", "changes_count": 113, "comments_count": 0}]
        }]'],
    ].collect{ |id, p|
      Validation.convert_locha_item({
        'locha_id' => -1,
        'objtype' => 'w',
        'id' => id,
        'p' => JSON.parse(p),
      })
    }

    r = Validation.time_machine_locha_propagate_rejection(config, locha, accept_all_validators).to_a
    assert_equal(11, r.size)

    duplicate_id = r.group_by{ |_locha_id, _matches, validation_result| validation_result.after_object.id }.find{ |_id, group| group.size > 1 }&.first
    assert_equal(3, duplicate_id)

    duplicates = r.select{ |_locha_id, _matches, validation_result| validation_result.after_object.id == 3 }
    assert_equal(3, duplicates.size)
    assert_equal(['reject'] * 3, duplicates.collect{ |_locha_id, _matches, validation_result| validation_result.action })
  end
end
