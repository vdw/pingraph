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
            borderColor: "rgba(99,102,241,0.2)",
            backgroundColor: "rgba(99,102,241,0.15)",
            borderWidth: 1,
            pointRadius: 0,
            fill: "+1",   // fill toward the next dataset (min)
            tension: 0.3
          },
          {
            // Smoke envelope — min boundary
            label: "Min RTT",
            data: min,
            borderColor: "rgba(99,102,241,0.2)",
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
            borderColor: "rgba(99,102,241,1)",
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
            labels: { filter: item => item.text !== "Min RTT" && item.text !== "Max RTT" }
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
            grid: { color: "rgba(0,0,0,0.05)" },
            ticks: { maxTicksLimit: 8, maxRotation: 0 }
          },
          y: {
            title: { display: true, text: "Latency (ms)" },
            min: 0,
            grid: { color: "rgba(0,0,0,0.05)" }
          }
        }
      }
    })
  }
}
