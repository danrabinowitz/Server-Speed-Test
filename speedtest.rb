#!/usr/bin/env ruby -w

require 'tempfile'
require 'set'
require_relative 'config.rb'


###########
# Set default configuration
server_params ||= [
  {:ip => '192.168.1.1', :protocol => :afp},
  {:ip => '192.168.1.2', :protocol => :afp, :afp_volume => 'IT Files'}
]

# 1 MB of random data
transfer_file_params ||= {:bytes => 1*1000*1000, :type => :random}

# Number of times to run the tests
number_of_times_to_run_tests = 3

#########
def shellescape(str)
  # An empty argument will be skipped, so return empty quotes.
  return "''" if str.empty?

  str = str.dup

  # Process as a single byte sequence because not all shell
  # implementations are multibyte aware.
  str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

  # A LF cannot be escaped with a backslash because a backslash + LF
  # combo is regarded as line continuation and simply ignored.
  str.gsub!(/\n/, "'\n'")

  return str
end
#########
# Define class
class Server

  attr_reader :ip, :protocol, :afp_destfile

  def initialize(params)
    raise "ip required" unless params[:ip]
    @ip = params[:ip]
    @protocol = params[:protocol] || :ssh

    if @protocol == :afp
      raise "afp_volume required" unless params[:afp_volume]
      @afp_volume = params[:afp_volume]
    end
  end
  
  def connect
    puts "Connecting to #{@ip} via #{@protocol}..."
    case @protocol
    when :afp
      if File::exists?("/Volumes/#{@afp_volume}")
        # abort "#{@afp_volume} may already be mounted. Please unmount and retry."
      else
        puts "Mounting volume: #{@afp_volume}..."
        cmd = "osascript -e 'tell application \"Finder\" to mount volume \"afp://192.168.120.3/@afp_volume\"'"
        puts "cmd: #{cmd}"
        system(cmd)
      end
      @afp_destfile = "/Volumes/#{@afp_volume}/speedtest_temporary_destfile.#{$$}"
    else
      raise "Attempt to connect with invalid protocol: #{@protocol}"
    end
  end

end

class TestFile < Tempfile
  
  attr_reader :bytes
  
  def initialize(params)
    raise "bytes required" unless params[:bytes]
    raise "basename required" unless params[:basename]

    @bytes = params[:bytes]
    @type = params[:type] || :random
    @basename = params[:basename]

    super(@basename)

    case @type
    when :random
      self.write(Array.new(@bytes) { rand(256) }.pack('c*'))    
    else
      raise "Attempt to initialize TestFile with invalid type: #{@type}"
    end
    
  end
end

class Test
  def initialize(params)
    raise "Test requires servers" unless params[:servers]
    raise "Test requires transfer_file" unless params[:transfer_file]
    
    @servers = params[:servers]
    @transfer_file = params[:transfer_file]
    @test_results = []
  end
  
  def run
    @servers.each do |server|
      @test_results << {:server => server, :upload_rate_bps => upload_rate_bps(server), :inplace_editing_ops_per_sec => inplace_editing_ops_per_sec(server), :download_rate_bps => download_rate_bps(server)}
      FileUtils.safe_unlink server.afp_destfile
    end
    @test_results
  end

  def upload_rate_bps(server)
#    puts "About to upload file to #{server.ip}"
    case server.protocol
    when :afp
#      puts "About to copy #{@transfer_file.path} to #{server.afp_destfile}"

      begin
        time_start = Time.now
        FileUtils.copy @transfer_file.path, server.afp_destfile
        time_finish = Time.now
      rescue
        STDERR.puts "Failed to copy #{@transfer_file.path} to #{server.afp_destfile}: #{$!}"
        raise
      end
    else
      raise "Unable to handle protocol type=#{server.protocol}"
    end
    
    duration_seconds = (time_finish - time_start)
#    puts "duration_seconds: #{duration_seconds}"
    upload_rate_bps = (@transfer_file.bytes*8) / duration_seconds
  end
  
  def inplace_editing_ops_per_sec(server)
#    puts "About to edit file inplace on #{server.ip}"
    ops = 100
    case server.protocol
    when :afp
      time_start = Time.now
      file1 = File.new(server.afp_destfile, "r+")
      ops.times do |n|
        file1.seek(Random.rand(@transfer_file.bytes - 1000))
        file1.getc
        file1.seek(Random.rand(@transfer_file.bytes))
        file1.write(Array.new(1000) { rand(256) }.pack('c*'))    
      end
      time_finish = Time.now
    end
    duration_seconds = (time_finish - time_start)
    ops / duration_seconds
  end

  def download_rate_bps(server)
#    puts "About to download file to #{server.ip}"
    case server.protocol
    when :afp
#      puts "About to copy #{server.afp_destfile} to #{@transfer_file.path}"

      begin
        time_start = Time.now
        FileUtils.copy server.afp_destfile, @transfer_file.path
        time_finish = Time.now
      rescue
        STDERR.puts "Failed to copy #{server.afp_destfile} to #{@transfer_file.path}: #{$!}"
        raise
      end
    else
      raise "Unable to handle protocol type=#{server.protocol}"
    end

    duration_seconds = (time_finish - time_start)
#    puts "duration_seconds: #{duration_seconds}"
    download_rate_bps = (@transfer_file.bytes*8) / duration_seconds
  end
  
end

#########
# Process configuration
# Create server objects
servers = Set.new
server_params.each {|server_param| servers << Server.new(server_param)}

servers.each do |server|
  server.connect
end

transfer_file = TestFile.new(transfer_file_params.merge({:basename => 'speedtest'}))

test_results = []
number_of_times_to_run_tests.times do |n|
  puts "About to run test ##{n+1}"
  Test.new(:servers => servers, :transfer_file => transfer_file).run.each {|r| test_results << r}
end

# servers.each do |server|
#   server.disconnect
# end

#puts test_results.inspect

printf "%20s %15s %15s %30s\n", '', 'Upload (bps)', 'Download (bps)', 'Inplace Editing (ops / sec)'
servers.each do |server|
  results_for_server = test_results.delete_if {|r| r[:server] != server}
  totals = results_for_server.inject {|sums, test_result| {:upload_rate_bps => sums[:upload_rate_bps] + test_result[:upload_rate_bps], :download_rate_bps => sums[:download_rate_bps] + test_result[:download_rate_bps], :inplace_editing_ops_per_sec => sums[:inplace_editing_ops_per_sec] + test_result[:inplace_editing_ops_per_sec]}}
  num = results_for_server.size
  printf "%20s %15.1f %15.1f %30.1f\n", server.ip, totals[:upload_rate_bps] / num, totals[:download_rate_bps] / num, totals[:inplace_editing_ops_per_sec] / num
end
