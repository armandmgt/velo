# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@hotwired/hotwire-native-bridge", to: "@hotwired--hotwire-native-bridge.js" # @1.2.2
pin "maplibre-gl" # @5.21.1
pin "chart.js" # https://cdn.jsdelivr.net/npm/chart.js@4.5.1/+esm
pin "kurklecolor" # https://cdn.jsdelivr.net/npm/@kurkle/color@0.3.4/+esm
pin "@stimulus-components/clipboard", to: "@stimulus-components--clipboard.js" # @5.0.0
pin "@stimulus-components/auto-submit", to: "@stimulus-components--auto-submit.js" # @6.0.0
