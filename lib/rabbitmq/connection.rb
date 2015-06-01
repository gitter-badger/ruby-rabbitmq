
module RabbitMQ
  class Connection
    def initialize *args
      @ptr  = FFI.amqp_new_connection
      @info = Util.connection_info(*args)
      create_socket!
      
      @finalizer = self.class.send :create_finalizer_for, @ptr
      ObjectSpace.define_finalizer self, @finalizer
    end
    
    def destroy
      if @finalizer
        @finalizer.call
        ObjectSpace.undefine_finalizer self
      end
      @ptr = @socket = @finalizer = nil
    end
    
    class DestroyedError < RuntimeError; end
    
    # @private
    def self.create_finalizer_for(ptr)
      Proc.new do
        FFI.amqp_connection_close(ptr, 200)
        FFI.amqp_destroy_connection(ptr)
      end
    end
    
    def user;     @info[:user];     end
    def password; @info[:password]; end
    def host;     @info[:host];     end
    def vhost;    @info[:vhost];    end
    def port;     @info[:port];     end
    def ssl?;     @info[:ssl];      end
    
    def max_channels;   @max_channels   ||= 0;      end; attr_writer :max_channels
    def max_frame_size; @max_frame_size ||= 131072; end; attr_writer :max_frame_size
    def heartbeat_interval; 0; end # not fully implemented in librabbitmq
    
    def start
      close # Close if already open
      connect_socket!
      login!
      open_channel!
    end
    
    def close
      raise DestroyedError unless @ptr
      FFI.amqp_connection_close(@ptr, 200)
    end
    
    private def parse_info url=nil
      
    end
    
    private def create_socket!
      raise DestroyedError unless @ptr
      
      @socket = FFI.amqp_tcp_socket_new(@ptr)
      Util.null_check :"creating a socket", @socket
    end
    
    private def connect_socket!
      raise DestroyedError unless @ptr
      raise NotImplementedError if ssl?
      
      create_socket!
      Util.error_check :"opening a socket",
        FFI.amqp_socket_open(@socket, host, port)
    end
    
    private def login!
      raise DestroyedError unless @ptr
      
      rpc_check :"logging in",
        FFI.amqp_login(@ptr, vhost, max_channels, max_frame_size,
          heartbeat_interval, :plain, :string, user, :string, password)
      
      @server_properties = FFI::Table.new(FFI.amqp_get_server_properties(@ptr)).to_h
    end
    
    private def open_channel!(number=1)
      raise DestroyedError unless @ptr
      
      FFI.amqp_channel_open(@ptr, number)
      rpc_check :"opening channel", FFI.amqp_get_rpc_reply(@ptr)
    end
    
    private def rpc_check action, res
      case res[:reply_type]
      when :library_exception; Util.error_check action, res[:library_error]
      when :server_exception;  raise NotImplementedError
      else res
      end
    end
  end
end
