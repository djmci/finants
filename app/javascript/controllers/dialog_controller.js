import { Controller } from "@hotwired/stimulus"

// Open a <dialog> by id.
export default class extends Controller {
  open() {
    document.getElementById(this.element.dataset.dialogId)?.showModal()
  }
}
