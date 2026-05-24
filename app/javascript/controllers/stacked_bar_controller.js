import { Controller } from "@hotwired/stimulus"

// Sizes each segment from its data-percent attribute via the CSSOM, so the
// markup needs no inline `style` attribute (keeps a strict CSP style-src happy;
// programmatic element.style writes are not governed by style-src).
export default class extends Controller {
  static targets = ["segment"]

  connect() {
    this.segmentTargets.forEach((segment) => {
      segment.style.width = `${segment.dataset.percent}%`
    })
  }
}
