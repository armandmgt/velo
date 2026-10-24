require "application_system_test_case"

class GearPickerTest < ApplicationSystemTestCase
  setup do
    gears(:road_bike).update!(default_sports: %w[bike])
    gears(:trail_shoes).update!(default_sports: %w[run])
    login(users(:one))
  end

  test "the picker follows the sport and preselects its default" do
    visit new_activity_url
    assert_no_field "Matériel"

    select "Vélo de route", from: "Sport"
    assert_selector :select, "Matériel", selected: "Vélo de course", options: [ "Aucun", "Gravel", "Vélo de course" ]

    select "Course à pied", from: "Sport"
    assert_selector :select, "Matériel", selected: "Chaussures de trail", options: [ "Aucun", "Chaussures de trail" ]

    select "Natation", from: "Sport"
    assert_no_field "Matériel"

    select "Gravel", from: "Sport"
    assert_selector :select, "Matériel", selected: "Aucun"
  end

  test "an upload keeps the gear picked in the form" do
    visit new_activity_url

    fill_in "Nom", with: "Sortie gravel"
    select "Vélo de route", from: "Sport"
    select "Gravel", from: "Matériel"
    attach_file "Fichier (FIT ou GPX)", file_fixture("gpx/ride.gpx").to_s
    click_on "Enregistrer"

    assert_text "Sortie gravel"
    assert_selector "a", text: "Gravel"
    assert_equal gears(:gravel_bike), Activity.find_by!(name: "Sortie gravel").gear
  end

  test "editing keeps the assigned gear when the sport's default differs" do
    activity = activities(:one)
    activity.update!(gear: gears(:gravel_bike))

    visit edit_activity_url(activity)

    assert_selector :select, "Matériel", selected: "Gravel"
  end
end
