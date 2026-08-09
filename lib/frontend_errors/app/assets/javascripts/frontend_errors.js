// Browser-side error reporter.
//
// Captures uncaught exceptions, unhandled promise rejections, Stimulus
// controller errors and Turbo failures, and posts them to the mounted engine,
// which reports them through Rails.error.
//
// Configuration comes from <meta name="frontend-errors"> (see TagsHelper).

const DEFAULTS = {
  endpoint: "/frontend_errors",
  maxReports: 10,
  maxMessageLength: 500,
  maxFrames: 30,
  flushDelay: 1000
}

// Messages that carry no actionable information. "Script error." is what
// browsers report for exceptions thrown by cross-origin scripts, and the
// ResizeObserver warnings are fired by layout timing rather than by a bug.
const IGNORED_MESSAGES = [
  /^Script error\.?$/,
  /^ResizeObserver loop/
]

const EXTENSION_SCHEME = /^(chrome|moz|safari-web|safari)-extension:\/\//

const config = { ...DEFAULTS }
const queue = []
const seen = new Set()

let started = false
let reported = 0
let reporting = false
let flushTimer = null

function readConfig() {
  const meta = document.querySelector("meta[name='frontend-errors']")
  if (!meta) return

  try {
    Object.assign(config, JSON.parse(meta.content))
  } catch {
    // A malformed tag shouldn't disable reporting; the defaults still work.
  }
}

function truncate(value, length) {
  const text = String(value ?? "")
  return text.length > length ? `${text.slice(0, length - 1)}…` : text
}

// Cross-origin and extension frames tell us nothing about our own code, and
// extensions in particular generate a lot of noise on other people's pages.
function isNoise(message, stack) {
  if (IGNORED_MESSAGES.some((pattern) => pattern.test(message))) return true
  if (!stack) return false

  const frames = stack.split("\n").filter((line) => /https?:|:\d+:\d+/.test(line))
  return frames.length > 0 && frames.every((line) => EXTENSION_SCHEME.test(line.trim().replace(/^at\s+/, "")))
}

function pageContext() {
  return {
    url: window.location.href,
    referrer: document.referrer || undefined,
    viewport: `${window.innerWidth}x${window.innerHeight}`
  }
}

export function report({ name, message, stack, source, context = {} }) {
  // A failure inside the reporter must never re-enter it.
  if (reporting || !started) return

  try {
    reporting = true

    const text = truncate(message, config.maxMessageLength)
    if (!text && !name) return
    if (isNoise(text, stack)) return

    const key = `${name}|${text}|${(stack || "").split("\n")[1] || ""}`
    if (seen.has(key)) return
    if (reported >= config.maxReports) return

    seen.add(key)
    reported += 1

    queue.push({
      name: name || "Error",
      message: text,
      stack: stack ? stack.split("\n").slice(0, config.maxFrames + 1).join("\n") : undefined,
      source,
      context: { ...pageContext(), ...context }
    })

    scheduleFlush()
  } catch {
    // Reporting is best-effort.
  } finally {
    reporting = false
  }
}

function scheduleFlush() {
  if (flushTimer) return
  flushTimer = setTimeout(() => flush(), config.flushDelay)
}

function flush({ beacon = false } = {}) {
  if (flushTimer) {
    clearTimeout(flushTimer)
    flushTimer = null
  }
  if (queue.length === 0) return

  const body = JSON.stringify({ reports: queue.splice(0, queue.length) })

  // On pagehide the document may be torn down before fetch resolves, so use
  // sendBeacon there; it can't set headers, which is why the endpoint is
  // CSRF-exempt.
  if (beacon && navigator.sendBeacon) {
    navigator.sendBeacon(config.endpoint, new Blob([body], { type: "application/json" }))
    return
  }

  fetch(config.endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
    keepalive: true,
    credentials: "same-origin"
  }).catch(() => {
    // Dropping a report is preferable to an unhandled rejection here, which
    // would come straight back through our own rejection handler.
  })
}

function errorFrom(value) {
  if (value instanceof Error) {
    return { name: value.name, message: value.message, stack: value.stack }
  }
  return { name: "Error", message: String(value) }
}

function onError(event) {
  if (event.error) {
    report({ ...errorFrom(event.error), source: "window" })
  } else if (event.message) {
    // Cross-origin scripts give an ErrorEvent with no Error object. The
    // location is still worth keeping, formatted so the server can resolve it.
    report({
      name: "Error",
      message: event.message,
      stack: event.filename ? `    at ${event.filename}:${event.lineno || 0}:${event.colno || 0}` : undefined,
      source: "window"
    })
  }
}

function onUnhandledRejection(event) {
  const { name, message, stack } = errorFrom(event.reason)
  report({ name: name === "Error" ? "UnhandledRejection" : name, message, stack, source: "promise" })
}

function onTurboFetchError(event) {
  const request = event.detail?.request
  report({
    name: "TurboFetchRequestError",
    message: `${request?.method || "GET"} ${request?.url || "request"} failed`,
    source: "turbo",
    context: { method: request?.method, url: request?.url?.toString() }
  })
}

function onTurboFrameMissing(event) {
  report({
    name: "TurboFrameMissing",
    message: `Response missing turbo-frame #${event.target?.id || "unknown"}`,
    source: "turbo",
    context: { frame_id: event.target?.id, status: event.detail?.response?.status }
  })
}

// Turbo Drive keeps the document alive across navigations, so a per-page-load
// budget has to be reset on visits rather than on load.
function onTurboLoad() {
  reported = 0
}

export function start() {
  if (started) return
  started = true

  readConfig()

  window.addEventListener("error", onError)
  window.addEventListener("unhandledrejection", onUnhandledRejection)
  document.addEventListener("turbo:fetch-request-error", onTurboFetchError)
  document.addEventListener("turbo:frame-missing", onTurboFrameMissing)
  document.addEventListener("turbo:load", onTurboLoad)

  window.addEventListener("pagehide", () => flush({ beacon: true }))
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") flush({ beacon: true })
  })
}

// Stimulus routes every controller lifecycle and action error through
// handleError, which only logs by default — so without this the majority of
// application errors never surface.
export function installStimulusErrorHandler(application) {
  const original = application.handleError.bind(application)

  application.handleError = (error, message, detail) => {
    report({
      ...errorFrom(error),
      source: "stimulus",
      context: { identifier: detail?.identifier }
    })
    original(error, message, detail)
  }
}
