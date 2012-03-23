#!/usr/bin/env ruby -w
###########
# Set default configuration

server_params ||= [
  {:ip => '192.168.1.1', :protocol => :afp},
  {:ip => '192.168.1.2', :protocol => :afp}
]

# 1 MB of random data
transfer ||= {:bytes => 1000*1000, :type => :random}

#########
# Define class
class Server
  def initialize(params)
    raise "ip required" if params[:ip].nil?
    ip = params[:ip]
    protocol = params[:protocol] || "ssh"
  end
end

#########
servers = []
server_params.each {|server_param| servers << Server.new(server_param)}

