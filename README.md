# ws_service
Easier, cleaner websocket services for Crystal web servers and web frameworks

`WS_Service` is a base class for WebSocket services,
that does a lot of the work for you:
* Provides middleware to accept the WebSocket connection automatically
  instantiate the class you have defined for that specifc service,
  not just in Crystal applications, but in _web frameworks_.
* Provides a versatile authentication interface so that you can authenticate
  or reject connecting clients with a few lines of code.
* Allows the client to easily pass any number of parameters before the connection
  is authenticated, so that you have all of the data you wish for authentication
  and initialization.
* Connects all WebSocket event handlers to your class methods automatically.
* Handles keepalive pings without your attention.

Services are implemented as classes that are children of `WS_Service`.
`WS_Middleware.instance` is a HTTP::Handler that connects to HTTP::Server and
accepts WebSocket connections for you, selecting the required WS_Service class
out of many potential services, and instantiating it per connection.

To use it, first connect `WS_Middleware.instance` to HTTP::Server. If you have
a stand-alone server, this is done as you instantiate HTTP::Server:
```crystal
 server = HTTP::Server.new([
   WS_Middleware.instance,
   # Additional handlers go here.
 ])
```
On a web framework, there is generally a file used to declare middleware. On
the Lucky web framework, it's `src/app_server.cr`, and it would be modified
this way:
```crystal
class AppServer < Lucky::BaseAppServer
  # Learn about middleware with HTTP::Handlers:
  # https://luckyframework.org/guides/http-and-routing/http-handlers
  def middleware : Array(HTTP::Handler)
    [
      WS_Middleware.instance, # Add this one.

      # There is a long list of handlers here.

    ] of HTTP::Handler
  end
```

Create your own service derived from `WS_Client`. Define a `self.path` class
method to return the path to your WebSocket service. For example, "/inform".
```crystal
class MyService < WS_Client
  # You must define a self.path method. It should start with a '/' character.
  def self.path
    "/inform"
  end
end
```
Your class will automatically be registered with `WS_Middleware.instance`, and when
`WS_Middleware.instance` gets a request for a WebSocket service with "/inform" as
the path, it will instantiate your class. There may be any number of different
WebSocket services, implement a child class of `WS_Service` for each one.

Implement whatever of these methods you need in your class:
```crystal
  # Authenticate the incoming connection. Return `true` if it should be accepted,
  # `false` otherwise. This is meant to be overridden by the derivative class.
  # The WebSocket isn't opened until after this method returns, so it's not possible
  # to send to the client in this method.
  def authenticate(
   # The requested path, without any query parameters.
   path : String,

   # A `URI::Params containing the query parmaeters, which can be used by the client
   # to send additional data for authentication and initialization. For example,
   # if they client connects to "ws://my.host/inform?a=1&b=2&c=Bruce",
   # params["a"] will contain "1", and params["c"] will contain "Bruce".
   params : URI::Params,

   # You may optionally implement subprotocols in your service. If you do, the client
   # can ask for one or more subprotocols, in order of preference. They will be
   # listed here. If you implement subprotocols, set `self.subprotocol=` to
   # the client-requested one you choose accept, in the `authenticate` method.
   # It will be returned in the "Sec-Websocket-Protocol" header in the response.
   requested_subprotocols : Array(String),

   # The HTTP request. You can read the headers from here, and other information
   # about the connection.
   request : HTTP::Request,

   # The address of the client, or nil if it can't be determined.
   remote_address : Socket::Address?
  ) : Bool
    true
  end

  # This is called when your WebSocket is connected. You may now send to the peer.
  def on_connect
  end

  # This is called when binary data is received.
  def on_binary(b : Bytes)
  end

  # This is called when the connection is closed.
  def on_close(code : HTTP::WebSocket::CloseCode, message : String)
  end

  # This is called when a string data is received.
  def on_message(message : String)
  end
end
```


There are methods available to your class for sending data and managing the
connection:
```crystal
   # This will send a binary message if the argument is `Bytes`, and a textual
   # message if the argument is `String`.
   send(data : String|Bytes)

   # Close the connection.
   close(
    code : HTTP::WebSocket::CloseCode = HTTP::WebSocket::CloseCode::NormalClose,
    message : String
   )

   # Is the connection open?
   is_open? : Bool
```

You can gracefully close all WS_Service connections by calling this:
```crystal
  WS_Service.graceful_shutdown(message : String)
```
This is generally done when shutting down a server, etc.

The connection is automatically closed in the `finalize` method of your class.
This will also gracefully close the WebSocket when your application exits, or when
your class is garbage-collected.

You can implement less-often-used methods which mirror those in WebSocket. But
`WS_Service` will send keep-alive pings to clients, and close connections to
unresponding clients, even if you don't.
```crystal
   # Called upon receipt of a ping.
   def on_ping(message : String)
   end

   # Called upon receipt of a pong.
   def on_pong(message : String)
   end
```
And these less-often-used methods are available to you for sending data pings and
pongs.
```crystal
   # Send a ping.
   ping(message : String)

   # Send a pong.
   pong(message : String)
```

There is a symmtrical shard for building clients, see
https://github.com/BrucePerens/ws_client .
It exports the same API as this class, but for clients.
