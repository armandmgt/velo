import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Connects to data-controller="bridge--authentication"
export default class extends BridgeComponent {
  static component = "authentication"

  connect() {
    super.connect()

    this.send("connect")
  }
}
