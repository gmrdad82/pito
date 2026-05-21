import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["table"]
  static values = { id: String, noUrl: { type: String, default: "no" } }

  connect() {
    if (!this._noUrl()) {
      this._restoreFromHash()
      window.addEventListener("hashchange", this._onHashChange)
    }
  }

  disconnect() {
    if (!this._noUrl()) {
      window.removeEventListener("hashchange", this._onHashChange)
    }
  }

  _onHashChange = () => {
    this._restoreFromHash()
  }

  sort(event) {
    const th = event.currentTarget
    const column = this._columnName(th)
    const wasAsc = th.classList.contains("sort-asc")
    const direction = wasAsc ? "desc" : "asc"

    this._sortByTh(th, direction)
    if (!this._noUrl()) this._updateHash(column, direction)
  }

  // 2026-05-18 — `data-sortable-table-no-url-value="yes"` opts a table
  // out of the URL-hash sort persistence. Used by tables that live
  // inside a modal (e.g. `Bundle::AllGamesTableComponent`) where
  // mirroring sort state into the page URL is wrong: the modal opens
  // and closes, but the URL would survive both. Honors the project's
  // "yes / no for external booleans" convention.
  _noUrl() {
    return this.noUrlValue === "yes"
  }

  _sortByTh(th, direction) {
    const allThs = Array.from(th.parentElement.children)
    const colIndex = allThs.indexOf(th)
    const type = th.dataset.sortType || "string"
    const tbody = this.tableTarget.querySelector("tbody")
    const rows = Array.from(tbody.querySelectorAll("tr"))

    this.tableTarget.querySelectorAll("th").forEach(h => {
      h.classList.remove("sort-asc", "sort-desc")
    })
    th.classList.add(`sort-${direction}`)

    rows.sort((a, b) => {
      const aCell = a.children[colIndex]
      const bCell = b.children[colIndex]
      const aVal = aCell?.querySelector("[data-sort-value]")?.dataset.sortValue ?? aCell?.textContent.trim() ?? ""
      const bVal = bCell?.querySelector("[data-sort-value]")?.dataset.sortValue ?? bCell?.textContent.trim() ?? ""

      let cmp
      if (type === "number") {
        cmp = (parseFloat(aVal.replace(/,/g, "")) || 0) - (parseFloat(bVal.replace(/,/g, "")) || 0)
      } else if (type === "date") {
        cmp = new Date(aVal) - new Date(bVal)
      } else {
        cmp = aVal.localeCompare(bVal, undefined, { sensitivity: "base" })
      }

      return direction === "asc" ? cmp : -cmp
    })

    rows.forEach(row => tbody.appendChild(row))
  }

  _columnName(th) {
    return th.textContent.trim().replace(/[▲▼⬍\s]/g, "").toLowerCase()
  }

  _tableKey() {
    return this.idValue || this.element.id || "0"
  }

  _updateHash(column, direction) {
    const params = this._parseHash()
    params.set(this._tableKey(), `${column}_${direction}`)
    const hash = Array.from(params.entries()).map(([k, v]) => `${k}=${v}`).join("&")
    history.replaceState(null, "", `${window.location.pathname}${window.location.search}#${hash}`)
  }

  _restoreFromHash() {
    const params = this._parseHash()
    const sort = params.get(this._tableKey())
    if (!sort) return

    const lastUnderscore = sort.lastIndexOf("_")
    if (lastUnderscore === -1) return
    const column = sort.substring(0, lastUnderscore)
    const direction = sort.substring(lastUnderscore + 1)
    if (direction !== "asc" && direction !== "desc") return

    const th = Array.from(this.tableTarget.querySelectorAll("th.sortable")).find(
      h => this._columnName(h) === column
    )
    if (th) this._sortByTh(th, direction)
  }

  _parseHash() {
    const hash = window.location.hash.replace(/^#/, "")
    const params = new Map()
    if (!hash) return params
    hash.split("&").forEach(pair => {
      const [k, v] = pair.split("=")
      if (k && v) params.set(decodeURIComponent(k), decodeURIComponent(v))
    })
    return params
  }
}
