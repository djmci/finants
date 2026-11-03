import { Controller } from "@hotwired/stimulus"

// Filters a list as you type — no server roundtrip, so the drawer
// never reloads. Items carry data-key (uppercase) to match against.
export default class extends Controller {
  static targets = [ "item", "empty", "hint" ]

  // Default view is pre-filtered to "preferred" rows (e.g. payees
  // already in the rule's category); typing searches the whole list.
  connect() { this.apply("") }

  filter(event) { this.apply(event.target.value) }

  apply(raw) {
    const q = raw.trim().toUpperCase()
    const anyPreferred = this.itemTargets.some((el) => el.dataset.preferred === "1")
    let shown = 0
    this.itemTargets.forEach((el) => {
      const show = q === ""
        ? !anyPreferred || el.dataset.preferred === "1"
        : el.dataset.key.includes(q)
      el.hidden = !show
      if (show) shown += 1
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
    if (this.hasHintTarget) this.hintTarget.hidden = q !== "" || !anyPreferred
  }
}
