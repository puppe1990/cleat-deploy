export const ChartTip = {
  mounted() {
    this.onMove = (event) => this.show(event)
    this.onLeave = () => this.hide()
    this.el.addEventListener("mousemove", this.onMove)
    this.el.addEventListener("mouseleave", this.onLeave)
    this.read()
  },

  updated() {
    this.read()
  },

  destroyed() {
    this.el.removeEventListener("mousemove", this.onMove)
    this.el.removeEventListener("mouseleave", this.onLeave)
  },

  read() {
    try {
      this.points = JSON.parse(this.el.dataset.points || "[]")
    } catch (_error) {
      this.points = []
    }
    this.viewWidth = Number(this.el.dataset.viewWidth || 400)
  },

  show(event) {
    if (!this.points.length) return

    const svg = this.el.querySelector("svg")
    const tip = this.el.querySelector("[data-chart-tip]")
    const hair = this.el.querySelector("[data-chart-line]")
    if (!svg || !tip) return

    const svgRect = svg.getBoundingClientRect()
    const x = ((event.clientX - svgRect.left) / Math.max(svgRect.width, 1)) * this.viewWidth
    let best = this.points[0]
    let bestDelta = Infinity

    for (const point of this.points) {
      const delta = Math.abs(point.x - x)
      if (delta < bestDelta) {
        bestDelta = delta
        best = point
      }
    }

    const left = (best.x / this.viewWidth) * svgRect.width
    const flip = best.x / this.viewWidth > 0.62

    tip.style.left = `${left}px`
    tip.style.transform = flip ? "translate(-108%, 0)" : "translate(8px, 0)"
    tip.querySelector("[data-chart-tip-label]").textContent = best.label || ""
    tip.querySelector("[data-chart-tip-value]").textContent = (best.lines || [best.value]).filter(Boolean).join("\n")
    tip.classList.remove("hidden")

    if (hair) {
      hair.style.left = `${left}px`
      hair.classList.remove("hidden")
    }
  },

  hide() {
    this.el.querySelector("[data-chart-tip]")?.classList.add("hidden")
    this.el.querySelector("[data-chart-line]")?.classList.add("hidden")
  },
}
