import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle() {
    const collapsed = this.element.classList.toggle("sidebar-collapsed")
    document.cookie = `sc=${collapsed ? 1 : 0};path=/;max-age=31536000;SameSite=Lax`
  }
}
