require "application_system_test_case"

class ActivitiesTest < ApplicationSystemTestCase
  test "importing an activity" do
    login(users(:one))

    visit activities_url

    click_on "Nouvelle activité"

    fill_in "Nom", with: "Sortie vélo"
    fill_in "Description", with: "Sortie vélo de 10km"
    select "Vélo de route", from: "Sport"
    attach_file "Fichier (FIT ou GPX)", file_fixture("gpx/ride.gpx").to_s

    click_on "Enregistrer"

    assert_text "Sortie vélo"
    # Guards the MapLibre pin: v6 dropped the default export and split the bundle
    # into chunks that resolve relative to the module URL, so a bad upgrade
    # leaves the map silently absent rather than failing anything else.
    assert_selector "canvas.maplibregl-canvas", wait: 15
  end

  test "naming an auto-imported activity from the dashboard banner" do
    login(users(:one))
    activity = activities(:awaiting_name)

    # `login` already lands on the dashboard (root_path).
    assert_text "Vos dernières sorties"

    field_id = "name_prompt_dashboard_#{activity.id}_name"
    fill_in field_id, with: "Sortie du matin"
    assert_field field_id, with: "Sortie du matin"

    within "#name_prompt_dashboard_#{activity.id}" do
      click_on "Enregistrer"
    end

    # The renamed activity drops out of the prompt without a full navigation.
    assert_no_selector "#dashboard_name_prompts", text: "Vos dernières sorties"
    assert_equal "Sortie du matin", activity.reload.name
  end
end
