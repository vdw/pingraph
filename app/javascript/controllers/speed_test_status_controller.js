import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    refreshUrl: String,
    running: Boolean,
    interval: Number
  }

  connect() {
    if (!this.runningValue) return
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.stopPolling()

    const delay = this.intervalValue || 3000
    this.timer = setInterval(() => this.refreshPanel(), delay)
  }

  stopPolling() {
    if (!this.timer) return
    clearInterval(this.timer)
    this.timer = null
  }

  async refreshPanel() {
    try {
      const response = await fetch(this.refreshUrlValue, {
        headers: { "Accept": "text/vnd.turbo-stream.html" }
      })
      if (!response.ok) return

      const body = await response.text()
      Turbo.renderStreamMessage(body)
    } catch {
      // Keep polling on transient network errors.
    }
  }
}
