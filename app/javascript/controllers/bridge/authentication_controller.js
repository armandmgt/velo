import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Connects to data-controller="bridge--authentication"
// Mounted by `sessions/_meta` whenever `authenticated?` is true. Its sole job
// is to fire a "connect" message to the native shell so the shell knows the
// current webview is rendering authenticated content and can swap from its
// unauthenticated root navigator to the tab bar.
export default class extends BridgeComponent {
  static component = "authentication"

  connect() {
    super.connect()
    this.send("connect")
  }
}
