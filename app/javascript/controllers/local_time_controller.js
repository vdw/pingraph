import { Controller } from "@hotwired/stimulus"

// Re-renders server timestamps in the viewer's timezone and locale. The server-rendered
// text (which always includes its zone) stays as the fallback when JavaScript is off.
export default class extends Controller {
  static values = {
    datetime: String,
    end: String,
    format: { type: String, default: "short" },
    suffix: String,
    attribute: String
  }

  connect() {
    const start = this.parse(this.datetimeValue || this.element.getAttribute("datetime"))
    if (!start) return

    const end = this.parse(this.endValue)
    let text = this.format(start)
    if (end) text += ` - ${this.format(end)}`
    text += this.suffixValue

    if (this.attributeValue) {
      this.element.setAttribute(this.attributeValue, text)
    } else {
      this.element.textContent = text
      this.element.title = start.toLocaleString(undefined, { dateStyle: "full", timeStyle: "long" })
    }
  }

  parse(value) {
    if (!value) return null
    const date = new Date(value)
    return isNaN(date) ? null : date
  }

  format(date) {
    switch (this.formatValue) {
      case "datetime":
        return `${date.getFullYear()}-${this.pad(date.getMonth() + 1)}-${this.pad(date.getDate())} ` +
          `${this.pad(date.getHours())}:${this.pad(date.getMinutes())}:${this.pad(date.getSeconds())}`
      case "long":
        return date.toLocaleString(undefined, { month: "long", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" })
      case "time":
        return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
      case "clock":
        return `${this.pad(date.getHours())}:${this.pad(date.getMinutes())}`
      default:
        return date.toLocaleString(undefined, { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" })
    }
  }

  pad(number) {
    return String(number).padStart(2, "0")
  }
}
