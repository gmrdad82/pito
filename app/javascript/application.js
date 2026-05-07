// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "Chart.bundle"
import "chartkick"

document.addEventListener("DOMContentLoaded", () => {
  if (!window.Chart) return
  const Chart = window.Chart

  // Global defaults
  Chart.defaults.font.family = 'ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace'
  Chart.defaults.font.size = 11
  Chart.defaults.color = getComputedStyle(document.documentElement).getPropertyValue("--color-muted").trim() || "#555555"
  Chart.defaults.animation = false
  Chart.defaults.elements.point.radius = 0
  Chart.defaults.elements.point.hitRadius = 8
  Chart.defaults.elements.line.borderWidth = 1.5

  // Legend: rendered as HTML below the canvas (NOT inside it). Keeping the
  // legend out of the canvas means a chart with many series does not shrink
  // its plot area — every chart canvas keeps the same fixed height set via
  // Chartkick `height:`, and the legend wraps to as many rows as it needs
  // below the chart card. Bracketed [label] convention, colored per series.
  Chart.defaults.plugins.legend.display = false

  function ensureLegendContainer(chart) {
    // Mount the legend as a sibling of the Chartkick wrapper (which is the
    // canvas's parent element). This way the canvas stays at the height the
    // wrapper enforces, and the legend lives outside that wrapper so it
    // can grow freely below.
    const wrapper = chart.canvas.parentElement
    if (!wrapper || !wrapper.parentElement) return null
    const host = wrapper.parentElement
    let legend = host.querySelector(":scope > .chart-html-legend")
    if (!legend) {
      legend = document.createElement("div")
      legend.className = "chart-html-legend"
      host.insertBefore(legend, wrapper.nextSibling)
    }
    return legend
  }

  const htmlLegendPlugin = {
    id: "htmlLegend",
    afterUpdate(chart) {
      const legend = ensureLegendContainer(chart)
      if (!legend) return
      const mutedColor = getComputedStyle(document.documentElement)
        .getPropertyValue("--color-muted").trim() || "#888888"

      // Wipe and re-render
      while (legend.firstChild) legend.removeChild(legend.firstChild)

      chart.data.datasets.forEach((ds, i) => {
        const meta = chart.getDatasetMeta(i)
        const hidden = meta.hidden
        const color = ds.borderColor || ds.backgroundColor || mutedColor
        const item = document.createElement("a")
        item.href = "#"
        item.className = "chart-html-legend__item"
        item.textContent = `[${ds.label}]`
        item.style.color = hidden ? mutedColor : color
        item.dataset.hidden = hidden ? "yes" : "no"
        item.addEventListener("click", (e) => {
          e.preventDefault()
          const isHidden = chart.getDatasetMeta(i).hidden
          chart.setDatasetVisibility(i, isHidden) // toggle
          chart.update()
        })
        legend.appendChild(item)
      })
    }
  }

  Chart.register(htmlLegendPlugin)

  // Synced crosshair state — charts in the same group share hover index
  const syncState = {} // { groupName: { index, sourceChartId } }

  function getSyncGroup(chart) {
    const canvas = chart.canvas
    const container = canvas.closest("[data-sync-group]")
    return container ? container.dataset.syncGroup : null
  }

  function getSyncedCharts(group, excludeChart) {
    if (!group || !window.Chartkick) return []
    return Object.values(Chartkick.charts)
      .map(c => c.getChartObject())
      .filter(c => c && c !== excludeChart && getSyncGroup(c) === group)
  }

  // Crosshair plugin — vertical hairline with dots at intersections, with sync
  const crosshairPlugin = {
    id: "crosshair",

    afterEvent(chart, args) {
      if (chart.config.options?.plugins?.crosshair === false) return
      const group = getSyncGroup(chart)
      if (!group) return

      const event = args.event
      if (event.type === "mousemove" && chart.tooltip) {
        const active = chart.tooltip.getActiveElements()
        if (active.length) {
          const idx = active[0].index
          if (!syncState[group] || syncState[group].index !== idx || syncState[group].source !== chart.id) {
            syncState[group] = { index: idx, source: chart.id }
            getSyncedCharts(group, chart).forEach(sibling => {
              const ds0 = sibling.getDatasetMeta(0)
              if (!ds0 || !ds0.data[idx]) return
              sibling.tooltip.setActiveElements(
                sibling.data.datasets.map((_, di) => ({ datasetIndex: di, index: idx })),
                { x: ds0.data[idx].x, y: ds0.data[idx].y }
              )
              sibling.setActiveElements(
                sibling.data.datasets.map((_, di) => ({ datasetIndex: di, index: idx }))
              )
              sibling.update("none")
            })
          }
        }
      }
      if (event.type === "mouseout") {
        if (syncState[group]?.source === chart.id) {
          delete syncState[group]
          getSyncedCharts(group, chart).forEach(sibling => {
            sibling.tooltip.setActiveElements([], {})
            sibling.setActiveElements([])
            sibling.update("none")
          })
        }
      }
    },

    afterDraw(chart) {
      if (chart.config.options?.plugins?.crosshair === false) return
      const tooltip = chart.tooltip
      if (!tooltip || !tooltip.getActiveElements().length) return

      const ctx = chart.ctx
      const x = tooltip.caretX
      const topY = chart.scales.y ? chart.scales.y.top : chart.chartArea.top
      const bottomY = chart.scales.y ? chart.scales.y.bottom : chart.chartArea.bottom

      // Draw vertical hairline
      ctx.save()
      ctx.beginPath()
      ctx.moveTo(x, topY)
      ctx.lineTo(x, bottomY)
      ctx.lineWidth = 1
      ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue("--color-muted").trim() || "#999999"
      ctx.setLineDash([3, 3])
      ctx.stroke()
      ctx.restore()

      // Draw dots at each dataset intersection
      const activeElements = tooltip.getActiveElements()
      activeElements.forEach((el) => {
        const meta = chart.getDatasetMeta(el.datasetIndex)
        const point = meta.data[el.index]
        if (!point) return

        ctx.save()
        ctx.beginPath()
        ctx.arc(point.x, point.y, 4, 0, Math.PI * 2)
        ctx.fillStyle = meta.dataset.options.borderColor || "#0000cc"
        ctx.fill()
        ctx.lineWidth = 1.5
        ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue("--color-bg").trim() || "#ffffff"
        ctx.stroke()
        ctx.restore()
      })
    }
  }

  Chart.register(crosshairPlugin)

  // Tooltip: show all datasets at the hovered x position
  Chart.defaults.interaction.mode = "index"
  Chart.defaults.interaction.intersect = false
  Chart.defaults.plugins.tooltip.position = "nearest"

  // Theme-aware chart recoloring — reads --color-chart-N CSS vars
  function getChartColors() {
    const style = getComputedStyle(document.documentElement)
    return [1, 2, 3, 4, 5].map(n => style.getPropertyValue(`--color-chart-${n}`).trim()).filter(Boolean)
  }

  function recolorCharts() {
    if (!window.Chartkick) return
    const colors = getChartColors()
    if (!colors.length) return

    const style = getComputedStyle(document.documentElement)
    const mutedColor = style.getPropertyValue("--color-muted").trim() || "#555555"
    const gridColor = style.getPropertyValue("--color-chart-grid").trim() || "#eeeeee"
    const tooltipBg = style.getPropertyValue("--color-tooltip-bg").trim() || "rgba(0,0,0,0.8)"
    const tooltipText = style.getPropertyValue("--color-tooltip-text").trim() || "#ffffff"

    Chart.defaults.color = mutedColor

    Object.values(Chartkick.charts).forEach(ck => {
      const chart = ck.getChartObject()
      if (!chart) return
      chart.data.datasets.forEach((ds, i) => {
        const color = colors[i % colors.length]
        if (ds.type === "bar" || chart.config.type === "bar") {
          ds.backgroundColor = color
        } else {
          ds.borderColor = color
          ds.pointBackgroundColor = color
        }
      })
      const scales = chart.options.scales
      if (scales?.x) {
        scales.x.ticks = { ...scales.x.ticks, color: mutedColor }
        scales.x.grid = { ...scales.x.grid, color: gridColor }
      }
      if (scales?.y) {
        scales.y.ticks = { ...scales.y.ticks, color: mutedColor }
        scales.y.grid = { ...scales.y.grid, color: gridColor }
      }
      chart.options.plugins.tooltip = {
        ...chart.options.plugins.tooltip,
        backgroundColor: tooltipBg,
        titleColor: tooltipText,
        bodyColor: tooltipText
      }
      chart.update("none")
    })
  }

  // Recolor after Chartkick finishes rendering
  setTimeout(recolorCharts, 100)

  // Expose for theme controller to call on toggle
  window.recolorCharts = recolorCharts
})
