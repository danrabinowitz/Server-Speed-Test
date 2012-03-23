#!/usr/bin/env ruby -w

###########
# Set default configuration
server_params ||= [
  {:ip => '192.168.1.1', :protocol => :afp},
  {:ip => '192.168.1.2', :protocol => :afp}
]

# 1 MB of random data
transfer_file_params ||= {:bytes => 1000*1000, :type => :random}


#########
# Define class
class Server
  def initialize(params)
    raise "ip required" if params[:ip].nil?
    ip = params[:ip]
    protocol = params[:protocol] || :ssh
  end
  
  def connect
    puts "Connecting to #{ip} via #{protocol}..."
  end
end

class TestFile << Tempfile
  def initialize(params)
    raise "bytes required" if params[:bytes].nil?
    bytes = params[:bytes]
    type = params[:type] || :random

    file = Tempfile.new('speedtest')
    super()
  end
end

#########
# Process configuration
# Create server objects
servers = []
server_params.each {|server_param| servers << Server.new(server_param)}

servers.each do |server|
  begin
    server.connect
  rescue
    raise
  end
end

transfer_file = TestFile.new(transfer_file_params)

