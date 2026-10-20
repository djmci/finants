import { Controller } from "@hotwired/stimulus"

// Global keyboard shortcuts. Ignores keystrokes while typing in fields.
export default class extends Controller {
  connect() {
    this.pendingG = false
    this.handler = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.handler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handler)
  }

  onKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (event.key === "Escape") {
      const drawer = document.querySelector(".drawer-toggle:checked")
      if (drawer) drawer.checked = false
      this.pendingG = false
      return
    }

    const target = event.target
    if (target.closest("input, textarea, select, [contenteditable]")) {
      this.pendingG = false
      return
    }

    if (this.pendingG) {
      this.pendingG = false
      const routes = { d: "/", t: "/transactions", a: "/accounts", c: "/categories" }
      const path = routes[event.key]
      if (path) {
        event.preventDefault()
        window.Turbo ? Turbo.visit(path) : (window.location.href = path)
      }
      return
    }

    switch (event.key) {
      case "g":
        this.pendingG = true
        break
      case "n":
        event.preventDefault()
        window.Turbo ? Turbo.visit("/transactions?new=1") : (window.location.href = "/transactions?new=1")
        break
      case "m":
        event.preventDefault()
        this.toggleTheme()
        break
      case "?": {
        const modal = document.getElementById("shortcuts_modal")
        if (modal) modal.showModal()
        break
      }
    }
  }

  toggleTheme() {
    const current = document.documentElement.dataset.theme ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "forest" : "emerald")
    const next = current === "forest" ? "emerald" : "forest"
    document.documentElement.dataset.theme = next
    document.cookie = `theme=${next};path=/;max-age=31536000;SameSite=Lax`
  }
}
