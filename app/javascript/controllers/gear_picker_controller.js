import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="gear-picker"
export default class extends Controller {
  static targets = ["field", "select"]
  static values = { catalogue: Array, kinds: Object }

  sportChanged(event) {
    const sport = event.target.value
    const choices = this.catalogueValue.filter((gear) => gear.kind === this.kindsValue[sport])
    const current = choices.find((gear) => String(gear.id) === this.selectTarget.value)
    const preferred = choices.find((gear) => gear.defaultSports.includes(sport)) ?? current

    this.#renderOptions(choices, preferred)

    const offered = choices.length > 0
    this.fieldTarget.hidden = !offered
    this.selectTarget.disabled = !offered
  }

  #renderOptions(choices, selected) {
    const blank = new Option("Aucun", "")
    const options = choices.map((gear) => new Option(gear.name, String(gear.id)))
    this.selectTarget.replaceChildren(blank, ...options)
    this.selectTarget.value = selected ? String(selected.id) : ""
  }
}
