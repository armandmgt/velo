import { Controller } from "@hotwired/stimulus"

// Highlights the selected best effort's stretch on the activity map; selecting
// it again clears the highlight.
export default class extends Controller {
  static targets = [ "effort" ]
  static outlets = [ "map" ]

  #selected = null

  select({ currentTarget, params: { start, end } }) {
    const deselect = this.#selected === currentTarget
    this.effortTargets.forEach((effort) => effort.setAttribute("aria-pressed", "false"))
    this.#selected = deselect ? null : currentTarget

    if (!this.hasMapOutlet) return
    if (deselect) {
      this.mapOutlet.clearStretch()
    } else {
      currentTarget.setAttribute("aria-pressed", "true")
      this.mapOutlet.highlightStretch(start, end)
    }
  }
}
