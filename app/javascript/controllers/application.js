import { Application } from "@hotwired/stimulus"
import { installStimulusErrorHandler } from "solid_errors_frontend"

const application = Application.start()

// Stimulus routes every controller lifecycle and action error through
// handleError, which only logs — without this they never leave the browser.
installStimulusErrorHandler(application)

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

export { application }
