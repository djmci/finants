import { Controller } from "@hotwired/stimulus"

// Keeps scroll position across turbo renders that land back on the
// same path (redirect-back saves, anchored edit links). Turbo ignores
// URL fragments on visits, so anchors alone can't do this.
let lastScrollY = 0
let lastPath = null

export default class extends Controller {
  connect() {
    this.save = () => { lastScrollY = window.scrollY; lastPath = location.pathname }
    this.restore = () => {
      requestAnimationFrame(() => {
        if (location.pathname === lastPath) window.scrollTo(0, lastScrollY)
      })
    }
    document.addEventListener("turbo:before-render", this.save)
    document.addEventListener("turbo:render", this.restore)
    document.addEventListener("turbo:load", this.restore)
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.save)
    document.removeEventListener("turbo:render", this.restore)
    document.removeEventListener("turbo:load", this.restore)
  }
}
