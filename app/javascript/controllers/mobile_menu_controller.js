import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "panel"]

  toggle() {
    const expanded = this.buttonTarget.getAttribute("aria-expanded") === "true"

    this.buttonTarget.setAttribute("aria-expanded", (!expanded).toString())
    this.panelTarget.classList.toggle("hidden")
  }
}
