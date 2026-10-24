import { Controller } from "@hotwired/stimulus"

// Copies the suggested FTP into the field without saving: the rider still has
// to submit the form to adopt it.
export default class extends Controller {
  static targets = ["input"]
  static values = { watts: Number }

  apply() {
    this.inputTarget.value = this.wattsValue
    this.inputTarget.focus()
  }
}
