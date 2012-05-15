#!/usr/bin/env ruby -w
require 'tempfile'
require 'set'
require_relative 'speedtest_library.rb'
require_relative 'config.rb'

###########
# Set default configuration
server_params = SpeedTestConfig.server_params

# 1 MB of random data
transfer_file_params ||= {:bytes => 4*1000*1000, :type => :random}

# Number of times to run the tests
number_of_times_to_run_tests = 2

#########
# Process configuration
# Create server objects
servers = Set.new
server_params.each {|server_param| servers << Server.new(server_param)}

# Create file of test data
transfer_file = TestFile.new(transfer_file_params.merge({:basename => 'speedtest'}))

# Run tests
test_results = []
number_of_times_to_run_tests.times do |n|
  puts "About to run test ##{n+1}"
  Test.new(:servers => servers, :transfer_file => transfer_file).run.each {|r| test_results << r}
end

# Display a report
#puts test_results.inspect
printf "%20s %15s %15s %30s\n", '', 'Upload (Mbps)', 'Download (Mbps)', 'Inplace Editing (ops / sec)'
servers.each do |server|
  results_for_server = test_results.reject {|r| r[:server] != server}
  totals = results_for_server.inject {|sums, test_result| {:upload_rate_bps => sums[:upload_rate_bps] + test_result[:upload_rate_bps], :download_rate_bps => sums[:download_rate_bps] + test_result[:download_rate_bps], :inplace_editing_ops_per_sec => sums[:inplace_editing_ops_per_sec] + test_result[:inplace_editing_ops_per_sec]}}
  num = results_for_server.size
  printf "%20s %15.2f %15.2f %30.2f\n", server.host, totals[:upload_rate_bps] / num / (1000 * 1000) , totals[:download_rate_bps] / num / (1000 * 1000), totals[:inplace_editing_ops_per_sec] / num
end
