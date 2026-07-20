import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Hotwire Native gives each tab its own web view. While a tab is not the
// visible one the OS suspends its web view and tears down the ActionCable
// connection, so any Turbo Stream refresh broadcast sent while the tab was
// hidden is missed — and missed broadcasts are never replayed. The tab would
// otherwise show stale content (old stats, a missing activity) until manually
// reloaded.
//
// Bridge that gap: whenever the page becomes visible again, ask Turbo to
// refresh the current page. Because the layout sets `turbo-refresh-method:
// morph`, this is a smooth in-place morph (scroll preserved), so a backgrounded
// tab catches up the moment the user returns to it. Only mounted inside the
// native shell; on the web the socket stays connected in background tabs so the
// live broadcast already suffices.
export default class extends Controller {
  connect() {
    this.refreshWhenVisible = this.refreshWhenVisible.bind(this)
    document.addEventListener("visibilitychange", this.refreshWhenVisible)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.refreshWhenVisible)
  }

  refreshWhenVisible() {
    if (document.visibilityState !== "visible") return

    Turbo.visit(window.location.href, { action: "replace" })
  }
}
