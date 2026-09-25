import { Controller } from "@hotwired/stimulus"

// Fades out and removes a flash message after a delay. Click dismisses it right away.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    clearTimeout(this.timer)
    this.element.style.transition = "opacity 300ms ease"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 300)
  }
}
