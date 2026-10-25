import { Controller } from "@hotwired/stimulus"

// Shows the fields that apply to the selected probe type: any element with
// data-probe-types="http tcp" is visible only for those types.
export default class extends Controller {
  static targets = ["probeType", "address", "statusRange", "expectedCodeField"]
  static values = { placeholders: Object }

  connect() {
    this.update()
  }

  update() {
    const probeType = this.currentProbeType()

    this.element.querySelectorAll("[data-probe-types]").forEach((element) => {
      this.toggle(element, element.dataset.probeTypes.split(" ").includes(probeType))
    })
    if (this.hasAddressTarget && this.placeholdersValue[probeType]) {
      this.addressTarget.placeholder = this.placeholdersValue[probeType]
    }
    this.toggleExpectedCode()
  }

  toggleExpectedCode() {
    const showExpectedCode = this.currentProbeType() === "http" && this.statusRangeTarget.value === "exact"
    this.toggle(this.expectedCodeFieldTarget, showExpectedCode)
  }

  // A select on the new form; on the edit form, a read-only element carrying data-probe-type.
  currentProbeType() {
    return this.probeTypeTarget.value ?? this.probeTypeTarget.dataset.probeType
  }

  toggle(element, show) {
    element.classList.toggle("hidden", !show)
  }
}
