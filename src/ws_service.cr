require "http/server/handler"
require "ws_client"
require "log"

# Notes
# WebSockets are not restricted by the same-origin policy. So, you can check
# that the Origin header names your site, to protect naive users from cross-site
# websocket hijacking. This only protects naive users, crafty software can still
# put anything it wishes in the origin header.
#
# The `WebSocket#stream` method is not implemented here because the implementation
# doesn't work with our locking paradigm. You can do all that it does iteratively
# with `WebSocket#send`. It can be implemented, it just needs to be written to use
# `send` here, so that it locks correctly.

# Accept registrations of websocket protocols.
# Accept websocket connections on behalf of those protocols.
# This is meant to be part of a middleware stack associated with HTTP::Server.
class WS::Middleware
  include HTTP::Handler

  @@instance : self = self.new

  # This contains all of the registered protocols.
  @protocols : Hash(String, WS::Service.class)

  def initialize
    @protocols = Hash(String, WS::Service.class).new
  end

  def self.instance
    @@instance
  end

  # Accept a websocket connection from the client. 
  def call(c : HTTP::Server::Context)
    r = c.request
    h = r.headers

    # Recognize a request for an upgrade to websocket, with one of our registered
    # protocols.
    if r.method == "GET" \
     && (upgrade = h["Upgrade"]?) \
     && upgrade.compare("websocket", case_insensitive: true) \
     && (protocol_class = @protocols[r.path.sub(%r(/$), "")]?)
      protocol = protocol_class.new
      
      # Ask the protocol to authenticate the connection.
      if protocol.authenticate(
       # The requested path.
       path: r.path,

       # You can add URL query parameters to the path, to communicate additional data.
       params: r.query_params,

       # An array of the requested subprotocols, highest priority first.
       # If your code accepts a particular one, set `self.subprotocol=` to its
       # name, and the client will be notified.
       requested_subprotocols: upgrade.split(%r(,\s+)) || Array(String).new(0),

       # The HTTP::Request, so you can read the headers, etc.
       request: r,

       # The remote address of the client, or nil if it can't be determined.
       remote_address: r.remote_address
      )
        # The connection is authenticated.

        # If the WS::Service derivative class has set `self.subprotocol=` to the
        # selected subprotocol name, tell the client that the connection is using
        # that subprotocol in the Sec-WebSocket-Protocol header.
        if (ps = protocol.subprotocol)
          c.response.headers["Sec-WebSocket-Protocol"] = ps
        end

        # Upgrade the connection to websocket.
        handler = HTTP::WebSocketHandler.new do |socket, context|
          # Set up the connection. 
          protocol.internal_connect(socket)
          # Inform the protocol that it's connected.
        end
        # Tell the client that it's been upgraded.
        handler.call(c)
        return
      end
    end
    # If we can't upgrade to websocket, just ignore the Upgrade header and don't
    # send `101 Switching Protocols`.

    # Pass this on to the next HTTP::Handler in the middleware stack. 
    call_next(c)
  end

  def finalize
    @protocols.each do |key, value|
      value.graceful_shutdown
    end
  end

  def register(path : String, protocol : WS::Service.class)
    # Register the protocol. Strip trailing slash, and we'll strip that from the
    # incoming request.path as well, so that we won't mismatch on whether there 
    # is a trailing slash or not.
    @protocols[path.sub(%r(/$), "")] = protocol
  end

  def unregister(path : String)
    @protocols.delete(path)
  end
end

# Server version of WS::Protocol. Make a derivative of this class, and it will
# automatically be registered with WS::Middleware, and will handle service requests
# for its #path.
abstract class WS::Service < WS::Protocol
  # Automatically register any derived class that is *not* abstract.
  macro inherited
    {% if !@type.abstract? %}
      WS::Middleware.instance.register(self.path, self)
    {% end %}
  end

  @params : URI::Params? = nil

  # Kludge to allow us to declare an abstract class method.
  # Every derived class of WS::Service must declare the path string used to connect
  # to it. This has to be in a module, as Crystal won't allow an abstract class
  # method to be directly declared as `abstract def self.path`. It does
  # allow it to be declared in a module and then used to extend a class.
  module ClassMethods
    abstract def path : String;
  end
  extend ClassMethods

  @@connections = Hash(WS::Service, WS::Service).new
  property subprotocol : String?
  getter last_pong_received : Time
  @ping_fiber : Fiber?

  def initialize
    @last_pong_received = Time.unix(seconds: 0)
    @socket = nil
    @subprotocol = nil
  end

  def self.graceful_shutdown(message : String = "Graceful shutdown")
    @@connections.each do |key, value|
      value.graceful_shutdown(message)
    end
  end

  # Authenticate the incoming connection. Return `true` if it should be accepted,
  # `false` otherwise. This is meant to be overridden by the derivative class.
  # The WebSocket isn't opened until after this method returns, so it's not possible
  # to send to the client in this method.
  #
  # *path* is a `String` containing the requested path, without any query parameters.
  #
  # *params* are a `URI::Params containing the query parmaeters, which can be used to
  # send additional data.
  #
  # *requested_subprotocols* is an `Array` of `String` containing the names of the
  # requested subprotocols. If your code accepts one, set `self.subprotocols`
  # to the name of the accepted subprotocol, and this will be communicated to the
  # client in the `Sec-Websocket-Protocol` header. If you don't implement
  # subprotocols, # it's not necessary to set `self.subprotocols`.
  #
  # *request* is the `HTTP::Request`, including the headers sent with the
  # `Upgrade` request which requests the change to WebSocket.
  #
  # *remote_address* is the remote address of the client, or nil if that can't
  # be deterimend.
  def authenticate(
   path : String,
   @params : URI::Params,
   requested_subprotocols : Array(String),
   request : HTTP::Request,
   remote_address : Socket::Address?
  ) : Bool
    true
  end

  # This is called when your WebSocket is connected. You may now send to the peer.
  # `WS::Client` doesn't have this method, because the constructor doesn't return
  # until the connection is valid. In `WS::Service`, `#authenticate` is called before
  # the connection is made, to decide whether to make it or not. Then `#connect`
  # is called when the connection is actually valid.
  def on_connect
  end

  # This sets up the connection.
  def internal_connect(s : HTTP::WebSocket)
    super

    f = @ping_fiber = Fiber.new(name: "#{self.class.name} ping") do
      @last_pong_received = Time.utc
      while @socket
        # Time out if the client hasn't responded to a ping in 1 minute.
        if Time.utc - last_pong_received > 1.minute
          STDERR.puts "ping timeout"
          close(HTTP::WebSocket::CloseCode::NoStatusReceived, "ping timeout")
          break
        end
        begin
          ping("ping")
        rescue e : Exception
          Log.error { "Ping got #{e.class.name}: #{e.message}" }
          close(HTTP::WebSocket::CloseCode::AbnormalClosure, "ping failure")
          break
        end
        sleep 10
      end
      @ping_fiber = nil
    end
    f.enqueue
    Fiber.yield

    @@connections[self] = self

    connect
  end

  # Handle closure. The superclass method calls `#on_close`.
  def internal_close(code : HTTP::WebSocket::CloseCode, message : String)
    @@connections.delete(self)
    super
  end

  # This is called when a pong is received. It remembers what time it was received,
  # and this is saved in `@last_pong_received`. The ping fiber uses that value to
  # time out an unresponding connection. This method then calls the superclass
  # method, which calls `#on_pong` to notify the user.
  def internal_on_pong(message : String)
    @last_pong_received = Time.utc
    super
  end

  def params
    @params.not_nil!
  end
end

# Add another layer, providing a pre-defined JSON over-wire protocol.
abstract class WS::Service::JSON < WS::Service
  include WS::JSON
end

