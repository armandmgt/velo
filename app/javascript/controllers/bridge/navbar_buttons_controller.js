import { BridgeComponent, BridgeElement } from "@hotwired/hotwire-native-bridge"

// Connects to data-controller="bridge--navbar-buttons"
export default class extends BridgeComponent {
  static component = "navbar-buttons"
  static targets = ["item"]

  connect() {
    super.connect()

    const items = this.itemTargets.map(target => {
      const element = new BridgeElement(target)
      return {
        title: element.title,
        iosImage: element.bridgeAttribute("ios-image"),
        androidImage: element.bridgeAttribute("android-image"),
      }
    })

    this.send("connect", { items }, message => {
      const item = this.itemTargets[message.data.index]
      new BridgeElement(item).click()
    })
  }

  disconnect() {
    super.disconnect()
    this.send("disconnect")
  }
}
