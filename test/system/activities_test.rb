require "application_system_test_case"

class ActivitiesTest < ApplicationSystemTestCase
  test "importing an activity" do
    login(users(:one))

    visit activities_url

    click_on "Nouvelle activité"

    fill_in "Name", with: "Sortie vélo"
    fill_in "Description", with: "Sortie vélo de 10km"
    select "Vélo", from: "Sport"

    click_on "Enregistrer"

    assert_text "Sortie vélo"
  end
end
