import { Controller } from "@hotwired/stimulus"

// Auto-dismisses flash toasts after a delay and on click of the close button.
export default class extends Controller {
  static targets = ["item"]
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeouts = this.itemTargets.map((item) =>
      setTimeout(() => this.remove(item), this.delayValue)
    )
  }

  disconnect() {
    this.timeouts?.forEach(clearTimeout)
  }

  dismiss(event) {
    const item = event.target.closest("[data-flash-target='item']")
    if (item) this.remove(item)
  }

  remove(item) {
    item.classList.add("transition-opacity", "duration-300", "opacity-0")
    setTimeout(() => {
      item.remove()
      if (this.itemTargets.length === 0) this.element.remove()
    }, 300)
  }
}
