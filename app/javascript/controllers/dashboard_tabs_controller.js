import { Controller } from "@hotwired/stimulus"

// Toggles the dashboard period panels (Semaine / Mois / Année / Tout) and the
// active-tab styling without a server round-trip — every period is rendered
// server-side. Personal records only show on the "all" tab.
export default class extends Controller {
  static targets = ["tab", "panel", "records"]

  select(event) {
    this.show(event.currentTarget.dataset.period)
  }

  show(period) {
    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.period !== period)
    })

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.period === period
      tab.classList.toggle("bg-neutral", active)
      tab.classList.toggle("text-neutral-content", active)
      tab.classList.toggle("bg-base-100", !active)
      tab.classList.toggle("text-base-content", !active)
    })

    if (this.hasRecordsTarget) {
      this.recordsTarget.classList.toggle("hidden", period !== "all")
    }
  }
}
