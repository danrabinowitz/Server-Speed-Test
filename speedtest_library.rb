def filesystem(path)
  return nil unless File::exists?(path)
  `df -m #{path} | tail --lines=+2 | cut -f1 -d' '`.strip
end

def umount(path)
  filesystem = filesystem_initial = filesystem(path)
  c = 0
  begin
    puts "umount: c=#{c}" if c > 0
    break unless filesystem =~ /^afp_/

    cmd = "umount #{path}"
    system(cmd)
    sleep 1
    filesystem = filesystem(path)
    break if filesystem != filesystem_initial
    c+=1
  end while c < 5
  raise "Unable to unmount" unless c < 5
end

# Define classes
class Server

  attr_reader :host, :protocol, :afp_destfile

  def initialize(params)
    raise "host required" unless params[:host]
    @host = params[:host]
    @protocol = params[:protocol] || :ssh

    if @protocol == :afp
      raise "afp_volume required for host=#{@host}" unless params[:afp_volume]
      @afp_volume = params[:afp_volume]
    end
  end
  
  def connect
    puts "  Connecting to #{@host} via #{@protocol}..."
    case @protocol
    when :afp
      mount_point = "/Volumes/#{@afp_volume}"
      filesystem_initial = filesystem(mount_point)
      if filesystem_initial
        if filesystem_initial =~ /^afp_/
          
          raise "#{mount_point} is mounted already. In service to keeping this test reproducable, please unmount and then retry. Use:\numount #{mount_point}"
        elsif filesystem_initial =~ /^\/dev\//
          raise "#{mount_point} exists, but is not mounted. In service to keeping this test reproducable, please remove the directory and then retry. Use:\nrmdir #{mount_point}"
        else
          raise "Unhandled pattern for filesystem_initial: #{filesystem_initial}"
        end
      end

      # puts "Mounting volume at: #{mount_point}"
      
      cmd = "osascript -e 'tell application \"Finder\" to mount volume \"afp://#{@host}/#{@afp_volume}\"'"
#      puts "cmd: #{cmd}"
      `#{cmd}`

      raise "Unable to mount #{mount_point}" if filesystem(mount_point) == filesystem_initial
        
      @afp_destfile = "#{mount_point}/speedtest_temporary_destfile.#{$$}"
    else
      raise "Attempt to connect with invalid protocol: #{@protocol}"
    end
  end

  def disconnect
    puts "    Disconnecting from #{@host}..."
    case @protocol
    when :afp
      mount_point = "/Volumes/#{@afp_volume}"
      umount(mount_point)
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
      server.connect
      upload_rate_bps = upload_rate_bps(server)
      server.disconnect
      server.connect
      inplace_editing_ops_per_sec = inplace_editing_ops_per_sec(server)
      server.disconnect
      server.connect
      download_rate_bps = download_rate_bps(server)
      server.disconnect
      @test_results << {:server => server, :upload_rate_bps => upload_rate_bps, :inplace_editing_ops_per_sec => inplace_editing_ops_per_sec, :download_rate_bps => download_rate_bps}
    end
    @test_results
  end

  def upload_rate_bps(server)
#    puts "About to upload file to #{server.host}"
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
#    puts "About to edit file inplace on #{server.host}"
    ops = 30
    case server.protocol
    when :afp
      file1 = File.new(server.afp_destfile, "r+")
      time_start = Time.now
      ops.times do |n|
        file1.seek(Random.rand(@transfer_file.bytes - 1000))
        file1.read(1000)
        file1.seek(Random.rand(@transfer_file.bytes))
        file1.write(Array.new(1000) { rand(256) }.pack('c*'))    
      end
      time_finish = Time.now
      file1.close
    end
    duration_seconds = (time_finish - time_start)
    ops / duration_seconds
  end

  def download_rate_bps(server)
#    puts "About to download file to #{server.host}"
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

    FileUtils.safe_unlink server.afp_destfile

    duration_seconds = (time_finish - time_start)
#    puts "duration_seconds: #{duration_seconds}"
    download_rate_bps = (@transfer_file.bytes*8) / duration_seconds
  end
  
end