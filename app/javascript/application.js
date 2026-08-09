// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { start as startErrorReporting } from "frontend_errors"

// Controller modules are loaded lazily by stimulus-loading, so the handlers are
// installed before any of them evaluates.
startErrorReporting()
