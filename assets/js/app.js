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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import RoomMessages from "./hooks/RoomMessages"
import ChatMessageTextArea from "./hooks/ChatMessageTextArea"
import Thread from "./hooks/Thread"
import { VoiceChatHook } from "./hooks/voice_chat"

const hooks = {
  RoomMessages,
  ChatMessageTextArea,
  Thread,
  VoiceChat: VoiceChatHook
}
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const dateTimeFormat = new Intl.DateTimeFormat();
const resolvedOptions = dateTimeFormat.resolvedOptions();

console.log("Locale-based Time Zone:", resolvedOptions.timeZone);
let liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken,
    timezone: resolvedOptions.timeZone
  }
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

// Global event listener for opening voice chat windows
window.addEventListener("phx:open_voice_call_window", (e) => {
  console.log("GLOBAL: phx:open_voice_call_window event received", e.detail); // Debug log
  const { url, call_id } = e.detail;
  if (!url) {
    console.error("GLOBAL: URL is missing in event detail for phx:open_voice_call_window");
    return;
  }
  const windowName = `voice_call_${call_id || new Date().getTime()}`; 
  const windowFeatures = "width=450,height=700,resizable=yes,scrollbars=yes,status=yes,noopener,noreferrer";
  console.log(`GLOBAL: Attempting to open window: URL=${url}, Name=${windowName}`); // Debug log
  const newWindow = window.open(url, windowName, windowFeatures);
  if (newWindow) {
    console.log("GLOBAL: Window opened successfully or popup blocker might still intervene.");
  } else {
    console.error("GLOBAL: window.open returned null or undefined. Popup likely blocked without a chance for user interaction.");
  }
});

