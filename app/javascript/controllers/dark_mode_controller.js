import { Controller } from "@hotwired/stimulus"

// Attached to <html>. Reads localStorage on connect and exposes toggle().
export default class extends Controller {
  connect() {
    const saved = localStorage.getItem("darkMode")
    if (saved === "dark") {
      this.element.classList.add("dark")
    } else if (saved === "light") {
      this.element.classList.remove("dark")
    } else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
      this.element.classList.add("dark")
    }
  }

  toggle() {
    const isDark = this.element.classList.toggle("dark")
    localStorage.setItem("darkMode", isDark ? "dark" : "light")
  }
}
