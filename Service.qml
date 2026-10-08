import Quickshell
import Quickshell.Io

// Runs each time the plugin loads. All the thinking is in libexec/umami-first-run,
// which offers the setup once if Umami is not set up yet and otherwise does nothing.
Scope {
  Process {
    running: true
    command: [decodeURIComponent(Qt.resolvedUrl("libexec/umami-first-run").toString().replace(/^file:\/\//, ""))]
  }
}
