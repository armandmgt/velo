// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { start as startErrorReporting } from "solid_errors_frontend"

// Controller modules are loaded lazily by stimulus-loading, so the handlers are
// installed before any of them evaluates.
startErrorReporting()
