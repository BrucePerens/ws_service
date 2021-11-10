require "ws_service"

class MyService < WS::Service
  def self.path : String
    "/my_service"
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
  #
  def authenticate(
   path : String,
   params : URI::Params,
   requested_subprotocols : Array(String),
   request : HTTP::Request,
   remote_address : Socket::Address?
  ) : Bool
    STDERR.puts "Authenticate: params are #{params.inspect}"
    true
  end

  # This is called when your WebSocket is connected. You may now send to the client.
  def connect
    STDERR.puts "#{PROGRAM_NAME} Connected."
  end

  # This is called when binary data is received.
  def on_binary(b : Bytes)
    STDERR.puts "#{PROGRAM_NAME} Received binary #{b.inspect}"
  end

  # This is called when the connection is closed. It is not possible to send any
  # additional information to the WebSocket.
  def on_close(code : HTTP::WebSocket::CloseCode, message : String)
    STDERR.puts "#{PROGRAM_NAME} Closed: #{code.inspect}, #{message.inspect}"
  end

  # This is called when a string datum is received.
  def on_message(message : String)
    STDERR.puts "#{PROGRAM_NAME} Received message #{message.inspect}"
  end
end
