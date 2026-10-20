import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { open: Boolean }

  connect() {
    if (this.openValue) requestAnimationFrame(() => { this.element.checked = true })
  }
}
