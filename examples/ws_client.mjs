export class WSClient {
  /*
   * Create a WebSocket client with query parameters provided in the arguments.
   * For example, new wsClient("ws://foo.bar/", "a", 1, "b", 2, c, "Bruce") would open
   * "ws://foo.bar/?a=1&b=2&c=Bruce". Characters are URL-encoded as necessary.
   * If it fails, the onClose method will be called. There is no exception upon
   * failure, because opening is asynchronous and exceptions must be synchronous.
   *
   * *path* is the method, host, port, and path part of the URL, for example
   * "ws://localhost:5000/".
   *
   * *args* are the URL query parameters, in name, value pairs.
   * The query parameter names are always strings, query parameter values can be
   * strings, ints, floats.
   */
  constructor(path, ...args) {
    /*
     * Set this to some other value in your derived class constructor, after
     * calling super, if you want subprotocols. Call protocol() from your
     * onOpen, to see what subprotocol you got.
     */
    this.subProtocols = [];

    var params = new URLSearchParams();
    for (var index = 0; index < args.length; index += 2) {
      params.append(args[index], args[index + 1])
    }
    var p = path.concat("?", params.toString());
    var ws = new WebSocket(p, this.subProtocols);
    /*
     * It looks like a race condition to set ws.onopen after calling new WebSocket.
     * What if the websocket is opened before processing gets to that line?
     * But the multitasking semantics of Javascript are that tasks run to completion
     * before other tasks are started. Relatively long-duration processes like opening
     * a websocket are asynchronous. So, that asynchoronous open task can't start to
     * process until after all of the handlers are set.
     */

    /*
     * Set the callbacks to our class methods. You can override them by extending
     * the WSClient or WSClientJSON class in your own class.
     */
    ws.onerror = (event) => {this.onError(event);};
    ws.onopen = (event) => {this.onOpenInternal(event);};
    ws.onclose = (event) => {this.onClose(event);};
    ws.onmessage = (message) => {this.onMessage(message);};
    this.ws = ws;
    this.done = false; /* Tells wait_until_done() when the program's finished. */
  };

  /*
   * Set the binary type for onBinary() to "blob" or "arraybuffer".
   */
  binaryType(type) {
    this.ws.binaryType = type
  }
  
  /* Is this still open? */
  isOpen() {
    return (this.ws != null)
  }

  /* Called when the WebSocket is closed, or if the open fails. */
  onClose(event) {
    console.log("Websocket closed");
    this.done = true;
    this.ws = null;
  }

  /* Called for an error on the websocket */
  onError (event) {
    console.log(`Websocket: ${event.type}:`)
    console.table(event);
  }

  /* Called for the receipt of any message, text or binary. */
  onMessage (event) {
    console.log("Received message: " + event.data);
  }

  /* Called when the WebSocket is opened, asynchronously. */
  onOpen(event) {
    console.log("Websocket opened");
  }

  /* Internal version of onOpen, calls onOpen */
  onOpenInternal(event) {
    onOpen(event)
    if (window.hasOwnProperty('sendUUID') && window.sendUUID) {
      var s = window.localStorage;
      var uuid = s.getItem('$uuid$')
      if (uuid == null) {
        uuid = crypto.randomUUID();
        s.setItem('$uuid$', uuid);
      }
      this.sendJSON("$uuid$", { 'uuid': s.getItem('uuid') });
    }
  }

  /* Return the sub-protocol selected by the server. */
  protocol() {
    return this.ws.protocol;
  }

  /* Send data in a Blob or ArrayBuffer. Use sendText or sendJSON for Strings. */
  sendBinary(data) {
    this.ws.send(data);
  }

  /*
   * Send an object as JSON.
   * *type* a user-provided string indicating the type of the data. The string
   * "$text$" is reserved for internal use by this software.
   * *data* is the thing to be sent as JSON.
   */
  sendJSON(type, data) {
    this.ws.send(JSON.stringify({"type": type, "data": data}));
  }

  /*
   * Send a message intended to be presented to a person.
   * *message* must be a string.
   */
  sendText(message) {
    this.sendJSON("$text$", message);
  }

  /*
   * When testing your Javascript on Node rather than the browser, it is necessary
   * to keep the program running until the last callback from the connection.
   * This is not necessary in the browser. This actually breaks the expected
   * semantics of Javascript, which are that nothing blocks.
   */
  waitUntilClosed() {
    if (typeof(window) == 'undefined') {
      (function wait () { if (!done) setTimeout(wait, 1000) })();
    }
    else {
      console.log("Attempt to call waitUntilClosed ignored in browser.");
    }
  }
}

/*
 * WSClientJSON extends WSClient, providing a pre-defined over-wire protocol to
 * pass JSON objects, text messages indended for presentaiton for a person, and it
 * separates out binary messages for the derived class to handle.
 */
export class WSClientJSON extends WSClient {
  /*
   * Implement onMessage, as expected by WSClient.
   * Pass messages to onText, onJSON, onBinary, as appropriate.
   * Don't override this in derived classes of WSClientJSON. You
   * should be using WSClient instead, if you need to do that.
   */
  onMessage(event) {
    var type = typeof(event.data);
    if (type == "string") {
      var json = JSON.parse(event.data);
      if (json.type == "$text$") {
        this.onText(json.data);
      }
      else {
        this.onJSON(json.type, json.data);
      }
    }
    else {
      this.onBinary(event.data);
    }
  }

  /*
   * Handle all messages with a Blob or ArrayBuffer datum. Override this in your
   * derived class.
   */
  onBinary(data) {
    /*
     * Binary WebSocket messages are useful to transfer large data efficiently,
     * but are more work to extract.
     */
    console.log("Received binary message.")
  }

  /*
   * Handle all JSON messages. Override this in your derived class.
   * *type* is a user-provided string indicating the kind of data.
   * *data* is decoded JSON.
   */
  onJSON(type, data) {
    console.log(`Received JSON ${type}: `);
    console.table(data);
  }
  
  /*
   * Receive a string message intended for presentation to a person.
   * Override this in your derived class.
   */
  onText(message) {
    console.log("Received text message: " + message);
  }
}
