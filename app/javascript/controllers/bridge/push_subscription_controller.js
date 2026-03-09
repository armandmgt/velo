import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Connects to data-controller="bridge--push-subscription"
export default class extends BridgeComponent {
  static component = "push-subscription"

  async connect() {
    if (Object.hasOwn(document.body.dataset, "hotwireNative")) {
      this.subscribeNative()
    }
  }

  subscribeNative() {
    this.send("connect")
  }
}
