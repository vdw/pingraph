import { Controller } from "@hotwired/stimulus"
import { Chart, LineController, LineElement, PointElement, LinearScale, CategoryScale, Filler, Tooltip, Legend } from "chart.js"

Chart.register(LineController, LineElement, PointElement, LinearScale, CategoryScale, Filler, Tooltip, Legend)

export default class extends Controller {
  static values = { url: String }

  async connect() {
    const data = await this.fetchData()
    if (data.length === 0) {
      this.element.closest("[data-chart-container]").innerHTML =
        '<p class="text-gray-400 text-sm text-center py-8">No ping data yet. Probes will begin shortly.</p>'
      return
    }
    this.renderChart(data)
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  async fetchData() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" }
      })
      return await response.json()
    } catch {
      return []
    }
  }

  renderChart(data) {
    const dark = document.documentElement.classList.contains("dark")
    const gridColor   = dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.05)"
    const textColor   = dark ? "rgba(156,163,175,1)"   : "rgba(107,114,128,1)"
    const avgColor    = dark ? "rgba(129,140,248,1)"   : "rgba(99,102,241,1)"
    const envBorder   = dark ? "rgba(129,140,248,0.3)" : "rgba(99,102,241,0.2)"
    const envFill     = dark ? "rgba(129,140,248,0.12)": "rgba(99,102,241,0.15)"

    const labels = data.map(p => {
      const d = new Date(p.recorded_at)
      return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
    })
    const avg    = data.map(p => p.latency)
    const min    = data.map(p => p.min_latency)
    const max    = data.map(p => p.max_latency)

    this.chart = new Chart(this.element, {
      type: "line",
      data: {
        labels,
        datasets: [
          {
            // Smoke envelope — max boundary (filled down to min)
            label: "Max RTT",
            data: max,
            borderColor: envBorder,
            backgroundColor: envFill,
            borderWidth: 1,
            pointRadius: 0,
            fill: "+1",   // fill toward the next dataset (min)
            tension: 0.3
          },
          {
            // Smoke envelope — min boundary
            label: "Min RTT",
            data: min,
            borderColor: envBorder,
            backgroundColor: "transparent",
            borderWidth: 1,
            pointRadius: 0,
            fill: false,
            tension: 0.3
          },
          {
            // Average — the bold centerline
            label: "Avg RTT (ms)",
            data: avg,
            borderColor: avgColor,
            backgroundColor: "transparent",
            borderWidth: 2,
            pointRadius: 2,
            fill: false,
            tension: 0.3
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: {
            display: true,
            labels: {
              color: textColor,
              filter: item => item.text !== "Min RTT" && item.text !== "Max RTT"
            }
          },
          tooltip: {
            callbacks: {
              label: ctx => {
                if (ctx.dataset.label === "Min RTT" || ctx.dataset.label === "Max RTT") return null
                return ` ${ctx.parsed.y?.toFixed(2) ?? "–"} ms`
              }
            }
          }
        },
        scales: {
          x: {
            grid: { color: gridColor },
            ticks: { maxTicksLimit: 8, maxRotation: 0, color: textColor }
          },
          y: {
            title: { display: true, text: "Latency (ms)", color: textColor },
            min: 0,
            grid: { color: gridColor },
            ticks: { color: textColor }
          }
        }
      }
    })
  }
}
