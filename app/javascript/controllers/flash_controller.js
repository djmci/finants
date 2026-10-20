import { Controller } from "@hotwired/stimulus"

// Auto-dismissible flash alert.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.dismiss(), 6000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.remove()
  }
}
