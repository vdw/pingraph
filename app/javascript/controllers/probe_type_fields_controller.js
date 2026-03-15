import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["probeType", "tcpFields", "httpFields", "statusRange", "expectedCodeField"]

  connect() {
    this.update()
  }

  update() {
    const probeType = this.currentProbeType()

    this.toggle(this.tcpFieldsTarget, probeType === "tcp")
    this.toggle(this.httpFieldsTarget, probeType === "http")
    this.toggleExpectedCode()
  }

  toggleExpectedCode() {
    const showExpectedCode = this.currentProbeType() === "http" && this.statusRangeTarget.value === "exact"
    this.toggle(this.expectedCodeFieldTarget, showExpectedCode)
  }

  currentProbeType() {
    return this.probeTypeTarget.value
  }

  toggle(element, show) {
    element.classList.toggle("hidden", !show)
  }
}
