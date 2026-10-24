require "test_helper"

class MapPrivacyZonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    login(@user)
  end

  def zone_params(**overrides)
    { map_privacy_zone: { name: "Domicile", latitude: 45.1, longitude: 5.7, radius: 400, **overrides } }
  end

  test "renders the new zone form with a map picker" do
    get new_map_privacy_zone_url

    assert_response :success
    assert_select "form[data-controller=zone-picker]"
    assert_select "input[type=hidden][name='map_privacy_zone[latitude]']"
  end

  test "creates a zone at the picked point" do
    assert_difference -> { @user.map_privacy_zones.count } do
      post map_privacy_zones_url, params: zone_params
    end

    zone = @user.map_privacy_zones.last
    assert_redirected_to user_path(anchor: "map-visibility")
    assert_equal [ 5.7, 45.1 ], [ zone.center.x, zone.center.y ]
    assert_equal 400, zone.radius
  end

  test "rejects a zone without a picked point" do
    assert_no_difference -> { MapPrivacyZone.count } do
      post map_privacy_zones_url, params: zone_params(latitude: "", longitude: "")
    end

    assert_response :unprocessable_content
    assert_match "Emplacement doit être choisi sur la carte", response.body
  end

  test "rejects a radius outside 200 m–1.6 km" do
    post map_privacy_zones_url, params: zone_params(radius: 5000)

    assert_response :unprocessable_content
  end

  test "updates and deletes a zone" do
    zone = @user.map_privacy_zones.create!(latitude: 45.1, longitude: 5.7, radius: 200)

    patch map_privacy_zone_url(zone), params: zone_params(latitude: 45.2, radius: 1600)
    assert_redirected_to user_path(anchor: "map-visibility")
    assert_equal [ 45.2, 1600 ], [ zone.reload.center.y, zone.radius ]

    assert_difference -> { MapPrivacyZone.count }, -1 do
      delete map_privacy_zone_url(zone)
    end
  end

  test "can't touch another user's zone" do
    zone = users(:two).map_privacy_zones.create!(latitude: 45.1, longitude: 5.7, radius: 200)

    get edit_map_privacy_zone_url(zone)
    assert_response :not_found

    delete map_privacy_zone_url(zone)
    assert_response :not_found
    assert MapPrivacyZone.exists?(zone.id)
  end

  test "lists zones on the profile" do
    @user.map_privacy_zones.create!(name: "Travail", latitude: 45.1, longitude: 5.7, radius: 800)

    get user_url

    assert_select "#map-visibility li", text: /Travail.*800 m/m
  end
end
