// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/icarurss"
import topbar from "../vendor/topbar"

const defaultFaviconHref = "/favicon.ico"
const readerLayoutStorageKey = "icarurss:reader-layout:v1"
const desktopReaderLayout = window.matchMedia("(min-width: 1024px)")
const readerColumnMinimums = {
  sidebar: 240,
  list: 320,
  reader: 360,
}
const readerLayoutDefaults = {
  new_tab: {sidebar: 320},
  three_column: {sidebar: 280, list: 420},
}
const readerCssVariables = {
  new_tab: {sidebar: "--reader-sidebar-width-new-tab"},
  three_column: {
    sidebar: "--reader-sidebar-width-three-column",
    list: "--reader-list-width-three-column",
  },
}

const buildUnreadFavicon = (count) => {
  const badgeText = count > 9 ? "9+" : String(count)
  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
      <rect width="64" height="64" rx="16" fill="#111827"/>
      <path d="M18 16h28v6H35v24h-6V22H18z" fill="#f8fafc"/>
      <circle cx="48" cy="18" r="12" fill="#ef4444"/>
      <text x="48" y="22" text-anchor="middle" font-family="ui-sans-serif, system-ui, sans-serif" font-size="11" font-weight="700" fill="#fff">${badgeText}</text>
    </svg>
  `.trim()

  return `data:image/svg+xml,${encodeURIComponent(svg)}`
}

const setFavicon = (href) => {
  let favicon = document.getElementById("app-favicon")

  if (!favicon) {
    favicon = document.createElement("link")
    favicon.id = "app-favicon"
    favicon.rel = "icon"
    document.head.appendChild(favicon)
  }

  favicon.href = href
}

const ReaderChrome = {
  mounted() {
    this.dragState = null
    this.pointerMove = (event) => this.onPointerMove(event)
    this.pointerUp = () => this.stopResize()
    this.handlePointerDown = (event) => this.onPointerDown(event)
    this.handleDoubleClick = (event) => this.onDoubleClick(event)
    this.handleKeyDown = (event) => this.onKeyDown(event)
    this.handleWindowResize = () => this.applyReaderLayout()

    this.el.addEventListener("pointerdown", this.handlePointerDown)
    this.el.addEventListener("dblclick", this.handleDoubleClick)
    this.el.addEventListener("keydown", this.handleKeyDown)
    window.addEventListener("resize", this.handleWindowResize)

    this.applyReaderLayout()
    this.updateFavicon()
  },

  updated() {
    this.applyReaderLayout()
    this.updateFavicon()
  },

  destroyed() {
    this.stopResize()
    this.el.removeEventListener("pointerdown", this.handlePointerDown)
    this.el.removeEventListener("dblclick", this.handleDoubleClick)
    this.el.removeEventListener("keydown", this.handleKeyDown)
    window.removeEventListener("resize", this.handleWindowResize)
    setFavicon(defaultFaviconHref)
  },

  onPointerDown(event) {
    const handle = event.target.closest("[data-resizer]")

    if (!handle || event.button !== 0 || !desktopReaderLayout.matches) {
      return
    }

    const mode = this.currentLayoutMode()
    const widths = this.currentWidths()

    if (!widths) {
      return
    }

    event.preventDefault()

    this.dragState = {
      handle,
      mode,
      resizer: handle.dataset.resizer,
      startX: event.clientX,
      startWidths: widths,
    }

    handle.classList.add("is-dragging")
    document.body.classList.add("reader-is-resizing")
    window.addEventListener("pointermove", this.pointerMove)
    window.addEventListener("pointerup", this.pointerUp)
  },

  onPointerMove(event) {
    if (!this.dragState) {
      return
    }

    const deltaX = event.clientX - this.dragState.startX
    const nextWidths = {...this.dragState.startWidths}

    if (this.dragState.resizer === "sidebar") {
      nextWidths.sidebar = this.dragState.startWidths.sidebar + deltaX
    }

    if (this.dragState.resizer === "list") {
      nextWidths.list = this.dragState.startWidths.list + deltaX
    }

    const clampedWidths = this.clampWidths(this.dragState.mode, nextWidths)
    this.applyWidths(this.dragState.mode, clampedWidths)
    this.saveWidths(this.dragState.mode, clampedWidths)
  },

  onDoubleClick(event) {
    const handle = event.target.closest("[data-resizer]")

    if (!handle) {
      return
    }

    const mode = this.currentLayoutMode()
    const widths = this.clampWidths(mode, this.defaultWidths(mode))

    this.applyWidths(mode, widths)
    this.saveWidths(mode, widths)
  },

  onKeyDown(event) {
    const handle = event.target.closest("[data-resizer]")

    if (!handle || !desktopReaderLayout.matches) {
      return
    }

    const keyDirection = {ArrowLeft: -24, ArrowRight: 24}[event.key]

    if (!keyDirection) {
      return
    }

    event.preventDefault()

    const mode = this.currentLayoutMode()
    const widths = this.currentWidths()

    if (!widths) {
      return
    }

    const nextWidths = {...widths}

    if (handle.dataset.resizer === "sidebar") {
      nextWidths.sidebar += keyDirection
    }

    if (handle.dataset.resizer === "list") {
      nextWidths.list += keyDirection
    }

    const clampedWidths = this.clampWidths(mode, nextWidths)
    this.applyWidths(mode, clampedWidths)
    this.saveWidths(mode, clampedWidths)
  },

  stopResize() {
    if (this.dragState?.handle) {
      this.dragState.handle.classList.remove("is-dragging")
    }

    this.dragState = null
    document.body.classList.remove("reader-is-resizing")
    window.removeEventListener("pointermove", this.pointerMove)
    window.removeEventListener("pointerup", this.pointerUp)
  },

  applyReaderLayout() {
    const mode = this.currentLayoutMode()
    const widths = this.clampWidths(mode, this.savedWidths(mode) || this.defaultWidths(mode))

    this.applyWidths(mode, widths)
    this.saveWidths(mode, widths)
  },

  applyWidths(mode, widths) {
    const variables = this.cssVariables(mode)

    this.setRootVariable(variables.sidebar, widths.sidebar)

    if (variables.list) {
      this.setRootVariable(variables.list, widths.list)
    }
  },

  currentWidths() {
    const mode = this.currentLayoutMode()
    const defaults = this.defaultWidths(mode)
    const variables = this.cssVariables(mode)

    return {
      sidebar: this.resolveWidth(variables.sidebar, defaults.sidebar),
      list: this.resolveWidth(variables.list, defaults.list),
    }
  },

  resolveWidth(variableName, fallback) {
    if (!variableName) {
      return fallback
    }

    const value = Number.parseFloat(getComputedStyle(this.el).getPropertyValue(variableName))
    return Number.isFinite(value) ? value : fallback
  },

  clampWidths(mode, widths) {
    const layout = this.layout()

    if (!layout || !desktopReaderLayout.matches) {
      return widths
    }

    const gutter = this.gutterSize()
    const containerWidth = layout.getBoundingClientRect().width
    const sidebarMin = readerColumnMinimums.sidebar
    const listMin = readerColumnMinimums.list
    const readerMin = readerColumnMinimums.reader

    if (mode === "new_tab") {
      const maxSidebar = Math.max(sidebarMin, containerWidth - gutter - listMin)

      return {
        sidebar: this.clamp(widths.sidebar, sidebarMin, maxSidebar),
      }
    }

    const maxSidebar = Math.max(sidebarMin, containerWidth - widths.list - readerMin - gutter * 2)
    const sidebar = this.clamp(widths.sidebar, sidebarMin, maxSidebar)
    const maxList = Math.max(listMin, containerWidth - sidebar - readerMin - gutter * 2)

    return {
      sidebar,
      list: this.clamp(widths.list, listMin, maxList),
    }
  },

  defaultWidths(mode) {
    return {...(readerLayoutDefaults[mode] || readerLayoutDefaults.three_column)}
  },

  cssVariables(mode) {
    return readerCssVariables[mode] || readerCssVariables.three_column
  },

  layout() {
    return this.el.querySelector("#reader-layout")
  },

  currentLayoutMode() {
    return this.el.dataset.layoutMode || this.layout()?.dataset.layoutMode || "three_column"
  },

  gutterSize() {
    const value = Number.parseFloat(getComputedStyle(this.el).getPropertyValue("--reader-gutter-size"))
    return Number.isFinite(value) ? value : 14
  },

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  },

  setRootVariable(name, value) {
    if (!name || !Number.isFinite(value)) {
      return
    }

    document.documentElement.style.setProperty(name, `${value}px`)
  },

  savedWidths(mode) {
    try {
      const payload = window.localStorage.getItem(readerLayoutStorageKey)

      if (!payload) {
        return null
      }

      const parsed = JSON.parse(payload)
      return parsed?.[mode] || null
    } catch (_error) {
      return null
    }
  },

  saveWidths(mode, widths) {
    try {
      const payload = window.localStorage.getItem(readerLayoutStorageKey)
      const parsed = payload ? JSON.parse(payload) : {}
      parsed[mode] = widths
      window.localStorage.setItem(readerLayoutStorageKey, JSON.stringify(parsed))
    } catch (_error) {
      // Ignore storage failures and keep the in-memory layout active.
    }
  },

  updateFavicon() {
    const count = Number.parseInt(this.el.dataset.unreadCount || "0", 10)

    if (Number.isFinite(count) && count > 0) {
      setFavicon(buildUnreadFavicon(count))
    } else {
      setFavicon(defaultFaviconHref)
    }
  },
}

const ArticleListItem = {
  mounted() {
    this.onClick = (event) => {
      if (event.button !== 0) {
        return
      }

      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        event.stopPropagation()
        return
      }

      event.preventDefault()
      event.stopPropagation()
      this.pushEvent("select_article", {id: this.el.dataset.articleId})
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {ArticleListItem, ReaderChrome, ...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
