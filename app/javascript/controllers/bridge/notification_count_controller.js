import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"

// Connects to data-controller="bridge--notification-count"
export default class extends BridgeComponent {
  static component = "notification-count"
  static values = { count: Number }

  connect() {
    super.connect()

    this.send("connect", { count: this.countValue }, () => {})
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }
}
