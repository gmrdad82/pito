import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["table"]

  sort(event) {
    const th = event.currentTarget
    const allThs = Array.from(th.parentElement.children)
    const column = allThs.indexOf(th)
    const type = th.dataset.sortType || "string"
    const tbody = this.tableTarget.querySelector("tbody")
    const rows = Array.from(tbody.querySelectorAll("tr"))

    // toggle direction
    const wasAsc = th.classList.contains("sort-asc")
    // clear all sort indicators
    this.tableTarget.querySelectorAll("th").forEach(h => {
      h.classList.remove("sort-asc", "sort-desc")
    })

    const direction = wasAsc ? "desc" : "asc"
    th.classList.add(`sort-${direction}`)

    rows.sort((a, b) => {
      const aVal = a.children[column]?.textContent.trim() || ""
      const bVal = b.children[column]?.textContent.trim() || ""

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
}
