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

    const x = this.svgUserX(svg, event.clientX)
    if (x == null) return

    let best = this.points[0]
    let bestDelta = Infinity

    for (const point of this.points) {
      const delta = Math.abs(point.x - x)
      if (delta < bestDelta) {
        bestDelta = delta
        best = point
      }
    }

    const left = this.overlayX(svg, best.x)
    if (left == null) return

    tip.querySelector("[data-chart-tip-label]").textContent = best.label || ""
    tip.querySelector("[data-chart-tip-value]").textContent = (best.lines || [best.value])
      .filter(Boolean)
      .join("\n")
    tip.classList.remove("hidden")
    this.placeTip(tip, left)

    if (hair) {
      hair.style.left = `${left}px`
      hair.style.height = `${svg.getBoundingClientRect().height}px`
      hair.classList.remove("hidden")
    }
  },

  hide() {
    this.el.querySelector("[data-chart-tip]")?.classList.add("hidden")
    this.el.querySelector("[data-chart-line]")?.classList.add("hidden")
  },

  svgUserX(svg, clientX) {
    const ctm = svg.getScreenCTM()
    if (!ctm) return null

    const point = svg.createSVGPoint()
    point.x = clientX
    point.y = 0
    const userX = point.matrixTransform(ctm.inverse()).x
    return Math.min(this.viewWidth, Math.max(0, userX))
  },

  overlayX(svg, userX) {
    const ctm = svg.getScreenCTM()
    if (!ctm) return null

    const point = svg.createSVGPoint()
    point.x = userX
    point.y = 0
    return point.matrixTransform(ctm).x - this.el.getBoundingClientRect().left
  },

  placeTip(tip, hairLeft) {
    tip.style.transform = "none"
    tip.style.left = "0px"
    const tipWidth = tip.offsetWidth
    const layerWidth = this.el.clientWidth
    const margin = 4
    const centered = hairLeft - tipWidth / 2
    const left = Math.max(margin, Math.min(centered, layerWidth - tipWidth - margin))
    tip.style.left = `${left}px`
  },
}
