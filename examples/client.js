/*
 * Javascript client for ws_service.
 * Licensed under CC0, you may use this in your own code without encumberance.
 */

/* The target URL and its query parameters. Use wss:, not ws:, in production code. */
var base = "ws://localhost:5000/inform";
var params = new URLSearchParams();
params.append("a", "1");
params.append("b", "2");
params.append("c", "Bruce");
/* The requested subprotocols, in order of preference. Default is "" */
var subprotocols = [""];

/* Load the WebSocket module if it's not defined. This probably happens in Node */
if (typeof(WebSocket) == 'undefined') {
  var WebSocket = require('websocket').w3cwebsocket;
}

var url = base.concat("?", params.toString()); /* The complete URL with params. */
var done = false; /* Flag to tell this program to exit when running under Node */
var ws = new WebSocket(url, subprotocols) /* The connection. Opens asynchronously. */

/*
 * It looks like a race condition to set ws.onopen after calling new WebSocket.
 * What if the websocket is opened before processing gets to that line?
 * But the multitasking semantics of Javascript are that tasks run to completion
 * before other tasks are started. Relatively long-duration processes like opening
 * a websocket are asynchronous. So, that asynchoronous open task can't start to
 * process until after all of the handlers are set.
 */

/* Handle opening of the websocket. Detect the sub-protocol the server chose. */
ws.onopen = function(event) {
  console.log("Websocket opened with sub-protocol \"" + ws.protocol + "\"")
}

/* Handle reception of a message. */
ws.onmessage = function(event) {
  var type = typeof(event.data);
  if ( type == "string" ) {
    console.log("Received text message: " + event.data)
  }
  else {
    console.log("Received binary message.")
    /*
     * Binary WebSocket messages are useful to transfer large data efficiently,
     * but are more work to extract.
     */
  }
}

/* Handle close. Set *done* to cause the wait-loop below to exit. */
ws.onclose = function(event) {
  console.log("Websocket closed");
  done = true;
}

/*
 * When testing this code under Node, this keeps the program from exiting until
 * the connection is closed. Using it in the browser would cause problems, so
 * we test for the window object.
 */
if (typeof(window) == 'undefined') {
  (function wait () { if (!done) setTimeout(wait, 1000) })();
}
