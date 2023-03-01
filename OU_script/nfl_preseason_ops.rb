# frozen_string_literal: true

require 'httparty'
require 'json'
require 'time'
require 'base64'
require 'yaml'

# version date = 08/05/2022
# execute by running ruby NFL_Preseason_ops.rb
# Follow the prompts to get the desired result.
# Optional command line arguments:
# ARGV[0] = source_id
# ARGV[1] = action
# ARGV[2] = input source
# Example: ruby NFL_Preseason_ops.rb M2005 start_service SES_EVENTS_0001

# GCP Ingest Pair for Fox 4K, DO NOT CHANGE!
@pri_zixi_bro_ip = '35.186.190.52'
@bck_zixi_bro_ip = '35.194.88.18'

# ASCII values to colorization of standard output in the terminal.
class String
  def red
    "\e[31m#{self}\e[0m"
  end

  def green
    "\e[32m#{self}\e[0m"
  end

  def brown
    "\e[33m#{self}\e[0m"
  end

  def blue
    "\e[34m#{self}\e[0m"
  end

  def magenta
    "\e[35m#{self}\e[0m"
  end

  def cyan
    "\e[36m#{self}\e[0m"
  end

  def bg_red
    "\e[41m#{self}\e[0m"
  end

  def bg_green
    "\e[42m#{self}\e[0m"
  end

  def bg_magenta
    "\e[45m#{self}\e[0m"
  end

  def bold
    "\e[1m#{self}\e[22m"
  end
end

# Global variables
module GlobalVariables
  class << self
    attr_accessor :ou_service_list, :target_source_id, :target_callsign

    GlobalVariables.ou_service_list = %w[M2005 M2015]
  end
end

# Standard output text formats
module OutputText
  class << self
    def info(section, message)
      puts "#{"INFO #{section}".ljust(11, ' ').blue} | #{message}"
    end

    def warning(section, message)
      puts "#{"WARNING #{section}".ljust(11, ' ').brown} | #{message}"
    end

    def encoder_status_text(source_id, callsign, ip, hostname, status)
      puts "      #{source_id} | #{callsign.ljust(11, ' ')} | #{ip.ljust(15, ' ')} | " \
"#{hostname.ljust(25, ' ')} #{status}"
    end

    def user_input(message)
      puts "#{'USER INPUT'.magenta} | #{message}"
    end

    def question(message)
      puts "\n#{'QUESTION?'.green} ->  #{message}"
    end

    def status_bar(seconds, message)
      sleeper = (seconds.to_f / 100).to_f
      spinner = Enumerator.new do |e|
        loop do
          e.yield '|'
          e.yield '/'
          e.yield '-'
          e.yield '\\'
        end
      end

      1.upto(100) do |i|
        progress = '=' * (i / 2) unless i < 2
        printf("\r#{'INFO STATUS'.blue} | #{message} #{'[%-50s] %d%% %s'.red}", progress, i, spinner.next)
        sleep(sleeper) # Number of seconds divided by 100
      end
      puts ''
    end

    def confirmation(action)
      puts '-' * 25
      puts "CONFIRM #{action}".brown
      puts '-' * 25
    end

    def continue(user_entry)
      puts ''
      printf "Type #{user_entry.bold.green} to continue or #{'any other character'.red} to exit -->>:"
      prompt = $stdin.gets.chomp
      puts ''
      exit unless prompt == user_entry
    end
  end
end

# Everything related to Zixi Broadcasters
module Zixi
  class << self
    attr_accessor :zixi_pri, :zixi_bck

    def zixi_status
      { 'pri' => 'PRIMARY', 'bck' => 'BACKUP' }.each do |path, path_header|
        OutputText.info('ZIXI', "Current #{path_header.brown} Zixi Routing:")
        puts "     #{'INPUTS'.ljust(28, ' ')}  -->  OUTPUTS".brown
        zixi_routing(path)
      end
    end

    def zixi_routing(path)
      instance_variable_get("@zixi_#{path}").outputs.each do |source_id, values_hash|
        next unless Encoder.encoder_list.keys.any? { |key| source_id == key }

        puts "     #{values_hash[:stream_id].ljust(28, ' ')}  -->  #{values_hash[:output_name]}"
      end
      puts ''
    end
  end

  # Zixi Related Functions
  class Zixi
    attr_accessor :zixi_data, :inputs, :outputs, :selected_input, :selected_output

    def initialize(zixi_bro_ip)
      @inputs = []
      @outputs = Hash.new do |hash, source_id|
        hash[source_id] = { output_name: '', stream_id: '', stupid_id: '', callsign: '' }
      end
      @zixi_bro_ip = zixi_bro_ip

      zixi_input_streams
      zixi_output_streams
    end

    def zixi_request(url_append)
      url = "http://#{@zixi_bro_ip}:4444/#{url_append}"

      headers = { 'Content-Type' => 'text/plain', Authorization: "Basic #{password_convert}", Accept: '*/*',
                  'Cache-Control' => 'no-cache', Connection: 'keep-alive' }

      zixi_response = HTTParty.get(url, headers: headers, timeout: 10)

      request_error(zixi_response) if zixi_response.code != 200
      @zixi_data = JSON.parse(zixi_response.to_s)
      puts "#{@zixi_bro_ip} timed out" if @zixi_data.nil?
    end

    def request_error(zixi_response)
      puts zixi_response.error!
      puts zixi_response.error_type
      puts zixi_response.msg
    end

    def zixi_input_streams
      zixi_request('zixi/streams.json?complete=1')

      @zixi_data['streams'].each do |stream|
        next unless stream['id'].include?('NFLNAL')

        @inputs << stream['id']
      end

      @inputs = @inputs.sort
    end

    def zixi_output_streams
      zixi_request('zixi/outputs.json?complete=1')

      @zixi_data['outputs'].each do |output|
        source_id = output['name'].split('_')[0]
        callsign = output['name'].split('_')[1]

        next unless GlobalVariables.ou_service_list.any? { |i| i == source_id }

        @outputs.store(source_id, { output_name: output['name'], stream_id: output['stream_id'],
                                    stupid_id: output['id'], callsign: callsign })
      end

      @outputs = Hash[@outputs.sort]
    end

    def list_io(io)
      values_hash_param = case io
                          when 'inputs'
                            :stream_id
                          when 'outputs'
                            :output_name
                          end

      instance_variable_get("@#{io}").each do |source_id, values_hash|
        puts "     #{source_id.cyan} | #{values_hash[values_hash_param].split('_')[1]}"
      end

      puts ''
    end

    def open_ui
      system('open', "http://#{@zixi_bro_ip}:4444")
    end

    def route_service
      input_stream_id = selected_input
      output_stream_id = outputs[selected_output][:stream_id]

      if output_stream_id == input_stream_id
        OutputText.info('ZIXI', "Service mapping changes are not required for #{selected_output} on" \
" Zixi Broadcaster - #{@zixi_bro_ip}.")
      else
        OutputText.info('ZIXI', "Mapping service on Zixi Broadcaster -  #{@zixi_bro_ip}")

        stop_output
        zixi_request("zixi/redirect_client.json?id=#{outputs[selected_output][:stupid_id]}&" \
"stream=#{input_stream_id}")
        sleep(10)
        start_output
      end
    end

    def display_mapping(path)
      path_header = path.values[0]

      puts "#{path_header.ljust(8, ' ')}  #{selected_input}  -->  " \
"#{@outputs[selected_output][:output_name]}".magenta
    end

    def stop_output
      zixi_request("zixi/edit_output.json?id=#{outputs[selected_output][:stupid_id]}&on=0")
    end

    def start_output
      zixi_request("zixi/edit_output.json?id=#{outputs[selected_output][:stupid_id]}&on=1")
    end

    private

    # Converts zixi password to base64
    def password_convert
      zixi_params = YAML.load_file('zixi.yml')
      Base64.encode64("#{zixi_params['zixi_user']}:#{zixi_params['zixi_pwd']}")
    end
  end
end

# Everything related to the encoders
module Encoder
  class << self
    attr_accessor :encoder_list

    def encoder_status
      OutputText.info('ATEME', 'CURRENT STATUS:')

      encoder_list.each do |source_id, v|
        status = case v.status
                 when 'RUNNING'
                   " = #{' RUNNING  '.bg_green}"
                 when 'TERMINATED'
                   " = #{'TERMINATED'.bg_red}"
                 end

        OutputText.encoder_status_text(source_id, v.callsign, v.ip, v.hostname, status)
      end
    end

    def list_running
      puts "#{' ' * 19}-----  RUNNING ENCODERS  -----".blue
      encoder_list.reject! { |_source_id, v| v.status == 'TERMINATED' }
      encoder_list.each do |source_id, v|
        OutputText.encoder_status_text(source_id, v.callsign, v.ip, v.hostname, '')
      end
      puts ''
    end

    def list_terminated
      puts "#{' ' * 19}-----  TERMINATED ENCODERS  -----".blue
      encoder_list.reject! { |_source_id, v| v.status == 'RUNNING' }
      encoder_list.each do |source_id, v|
        OutputText.encoder_status_text(source_id, v.callsign, v.ip, v.hostname, '')
      end
      puts ''
    end

    def user_zixi_source_selection(io)
      until Zixi.zixi_pri.instance_variable_get("@#{io}").any? { |id| id.include? @source }
        OutputText.user_input("Enter a #{'SOURCE ID'.cyan} from the list:")
        @source = $stdin.gets.chomp.upcase
      end
    end
  end

  # Titan Related Functions
  class Encoder
    @running = {}
    @terminated = {}

    class << self
      attr_accessor :running, :terminated
    end

    attr_accessor :source_id, :ip, :hostname, :callsign, :status

    def initialize(source_id)
      @source_id = source_id

      find_encoder

      @status = encoder_status

      case @status
      when 'RUNNING'
        Encoder.running.store(source_id, @hostname)
      when 'TERMINATED'
        Encoder.terminated.store(source_id, @hostname)
      end
    end

    def find_encoder
      response = HTTParty.get("https://skynet-api.fubo.tv/api/v2/services/devices?source_id=#{@source_id}", timeout: 10)

      store_encoder_params(JSON.parse(response.body))
    end

    def store_encoder_params(skynet_data)
      @callsign = skynet_data[0]['service']

      skynet_data[0]['devices'].each do |device|
        next unless device['role'] == 'encoder'

        if device['name'].include?('east') || device['name'].include?('asbnva')
          @ip = device['public_ip']
          @hostname = device['name']
        end
      end
    end

    # Checks VM status via Jane API
    def encoder_status
      jane_api("gcpistatus?instance=#{@hostname}&zone=us-east4-a&project=fubo-encoders")
    end

    def start_vm
      OutputText.info('ATEME', "#{'STARTING'.green} Titan VM Instance #{@ip.cyan} | #{@hostname.cyan}")

      jane_api("startgcpi?instance=#{@hostname}&zone=us-east4-a&project=fubo-encoders")
      OutputText.status_bar(90, 'Waiting for Encoder to start up')
      OutputText.info('ATEME', "Encoder VM Instance Started: http://#{@ip}")
    end

    def stop_vm
      OutputText.info('ATEME', "#{'STOPPING'.red} Titan VM Instance #{@ip.cyan} | #{@hostname.cyan}")

      jane_api("stopgcpi?instance=#{@hostname}&zone=us-east4-a&project=fubo-encoders")
    end

    def open_ui
      system('open', "http://#{@ip}")
    end

    def start_service
      OutputText.info('ATEME', "#{'STARTING'.green} Service on #{@ip.cyan} | #{@hostname.cyan}")
      sleep(10)

      jane_api("start?sid=#{GlobalVariables.target_source_id.upcase}&ip=#{@ip}")
    end

    # Start/Stop Titan Service
    def stop_service
      OutputText.info('ATEME', "#{'STOPPING'.red} Service on #{@ip.cyan} | #{@hostname.cyan}")

      jane_api("stop?sid=#{GlobalVariables.target_source_id.upcase}&ip=#{@ip}")
    end

    def reprobe
      OutputText.info('ATEME', 'Re-probing encoder and setting PIDs.')

      jane_api("plant_pid_map?sid=#{GlobalVariables.target_source_id.upcase}&thumbs=FALSE")
    end

    def jane_api(url_append)
      url = "http://54.164.50.130/jane/#{url_append}"

      @jane_response = HTTParty.put(url, body: '', timeout: 20).read_body
    rescue Net::OpenTimeout, Errno::ECONNREFUSED, Net::ReadTimeout => e
      OutputText.warning('ENCODER',
                         "#{/\d+.\d+.\d+.\d+/.match(url)} : ERROR: timed out while trying to connect #{e}")
    end
  end
end

# Action Super Class
class ActionSuper
  def initialize
    nil
  end

  def zixi_output_service(list_output: false)
    Zixi.zixi_pri.list_io('outputs') if list_output
    user_zixi_source_selection('outputs') if @source.nil?

    Zixi.zixi_pri.selected_output = @source
    Zixi.zixi_bck.selected_output = @source
    GlobalVariables.target_source_id = @source
    GlobalVariables.target_callsign = Zixi.zixi_pri.outputs[@source][:callsign]
  end

  def zixi_input_source
    Zixi.zixi_pri.inputs.each { |input| @source = input if input.split('_')[0] == @source }

    Zixi.zixi_pri.selected_input = @source
    Zixi.zixi_bck.selected_input = @source.gsub('PRI', 'BCK')
    @source = ''
  end

  def user_zixi_source_selection(io)
    until Zixi.zixi_pri.instance_variable_get("@#{io}").any? { |id| id.include? @source }
      OutputText.user_input("Enter a #{'SOURCE ID'.cyan} from the list:")
      @source = $stdin.gets.chomp.upcase
    end
  end

  def select_service(message)
    OutputText.user_input("Enter a #{'SOURCE ID'.cyan} from the list:")
    @source = $stdin.gets.chomp.upcase

    select_service('is already running') if @source.empty?

    if Encoder.encoder_list.any? { |source_id, _v| source_id.include?(@source) }
      zixi_output_service
    else
      OutputText.warning('SCRIPT', "The encoder for #{@source.cyan} #{message}")
      puts ''
      @source = ''
      select_service(message)
    end
  end

  def target_service
    "#{GlobalVariables.target_source_id.cyan} | #{GlobalVariables.target_callsign.cyan}"
  end

  def confirmation(message)
    puts "\n#{message}"
    OutputText.info('ZIXI', 'CONFIRM ZIXI STREAM MAPPING')
    puts '          INPUTS                      -->  OUTPUTS'.brown
    Zixi.zixi_pri.display_mapping({ 'pri' => 'PRIMARY:' })
    Zixi.zixi_bck.display_mapping({ 'bck' => 'BACKUP:' })
  end

  def no_running_encoders(action)
    message = if action == 'SWITCH'
                'No services are running.'
              else
                'No encoders are currently running.'
              end

    OutputText.info('SCRIPT', "#{action.cyan} option is not available at this time. #{message}")
    puts "#{' ' * 19}Exiting the script.\n\n"
    exit
  end
end

# Starts a service
class ActionStartService < ActionSuper
  def initialize
    super
    OutputText.question("What service would you like to #{'START'.cyan}?")
    GlobalVariables.ou_service_list.each { |i| puts "    #{i}" }
    puts ''
    select_service('is already running')

    zixi_input_source
    confirm
    startup_sequence
  end

  def confirm
    confirmation_message =
      "You are about to #{'START'.bg_green} the following service and VM Instance: #{target_service}\n\n"

    confirmation(confirmation_message)
    OutputText.continue('y')
  end

  def startup_sequence
    target_source_id = GlobalVariables.target_source_id

    unless Encoder::Encoder.running.keys.any? { |i| i == target_source_id }
      Encoder.encoder_list[target_source_id].start_vm
    end

    Encoder.encoder_list[target_source_id].start_service
    Encoder.encoder_list[target_source_id].reprobe
  end
end

# Stop a service
class ActionStopService < ActionSuper
  def initialize
    super
    if Encoder::Encoder.running.empty?
      no_running_encoders('STOP')
    else
      OutputText.question("Which service would you like to #{'STOP'.cyan}?")
      stop
    end
  end

  def stop
    GlobalVariables.ou_service_list.each { |i| puts "    #{i}" }
    puts ''
    select_service('is already terminated.')

    stop_confirmation
    Encoder.encoder_list[GlobalVariables.target_source_id].stop_service
  end

  def stop_confirmation
    puts ''
    OutputText.warning('ATEME', "You are about to #{' STOP '.bg_red} the following service" \
" :  #{target_service}.")
    OutputText.continue('y')
  end
end

# Stop Encoder VM
class ActionStopVM < ActionSuper
  def initialize
    super
    if Encoder::Encoder.running.empty?
      no_running_encoders('STOP')
    else
      stop
    end
  end

  def stop
    stop_confirmation

    GlobalVariables.ou_service_list.each do |source_id|
      OutputText.info('ATEME', "Stopping service #{source_id}")
      GlobalVariables.target_source_id = source_id
      Encoder.encoder_list[source_id].stop_service
    end

    Encoder.encoder_list['M2005'].stop_vm
  end

  def stop_confirmation
    puts ''
    OutputText.warning('ATEME', "You are about to #{' STOP '.bg_red} both NFL ALT services and " \
'shut down the encoder.')
    OutputText.continue('y')
  end
end

# Initiates a switch of input/output on the Zixi Bro.
class ActionSwitch < ActionSuper
  def initialize
    super
    OutputText.question("Which service would you like to #{'SWITCH'.cyan} sources for?")
    zixi_output_service(list_output: true)
    zixi_input_source

    confirmation("You are about to #{'SWITCH THE INPUT'.cyan} for #{target_service}")
    OutputText.continue('y')

    switch
  end

  def switch
    Zixi.zixi_pri.stop_output
    Zixi.zixi_pri.route_service
    sleep(10)
    Zixi.zixi_pri.start_output

    Zixi.zixi_bck.stop_output
    Zixi.zixi_bck.route_service
    sleep(10)
    Zixi.zixi_bck.start_output

    return if Encoder::Encoder.terminated.include?(GlobalVariables.target_source_id)

    active_encoder
  end

  def active_encoder
    OutputText.info('ATEME',
                    "The encoder for #{GlobalVariables.target_source_id.cyan} is active.  Performing a re-probe.")
    sleep(15)
    Encoder.encoder_list[GlobalVariables.target_source_id].reprobe
  end
end

# Exits after displaying Zixi and Encoder status.
class ActionExit
  def initialize
    exit
  end
end

def current_status
  puts "\n\n       #{'CURRENT STATUS OF ENCODERS AND ZIXIS'.brown} \n #{('=' * 50).brown}"

  Encoder.encoder_status
  puts ''
  Zixi.zixi_status
end

def assign_action
  action_list = %w[start_service stop_service stop_vm exit]

  OutputText.user_input('What action would you like to take? (Enter the number):')

  action_list.each_with_index { |action, index| puts "     [ #{index} ] - #{action}" }
  action_index = $stdin.gets.chomp

  @action = action_list[action_index.to_i]

  return unless @action.nil?

  OutputText.user_input('Please enter a valid action:')
  assign_action
end

def action_class
  case @action
  when 'start_service'
    'StartService'
  when 'stop_service'
    'StopService'
  when 'stop_vm'
    'StopVM'
  when 'switch_source'
    'Switch'
  else
    @action.capitalize
  end
end

def route_service
  Zixi.zixi_pri.route_service
  sleep(10)
  Zixi.zixi_bck.route_service
end

def unaccompanied_action_sequence(action)
  target_source_id = GlobalVariables.target_source_id

  case action
  when 'start_service'
    route_service

    unless Encoder::Encoder.running.keys.any? { |i| i == target_source_id }
      Encoder.encoder_list[target_source_id].start_vm
    end

    Encoder.encoder_list[target_source_id].start_service
    Encoder.encoder_list[target_source_id].reprobe
  when 'stop_service'
    Encoder.encoder_list[target_source_id].stop_service
  when 'stop_vm'
    Encoder.encoder_list['M2005'].stop_service
    Encoder.encoder_list['M2015'].stop_service
    Encoder.encoder_list['M2005'].stop_vm
  end
end

# =================================================
# BEGIN SCRIPT EXECUTION
# =================================================
Zixi.zixi_pri = Zixi::Zixi.new(@pri_zixi_bro_ip)
Zixi.zixi_bck = Zixi::Zixi.new(@bck_zixi_bro_ip)
Encoder.encoder_list = Zixi.zixi_pri.outputs.transform_values do |v|
  Encoder::Encoder.new(v[:output_name].split('_')[0])
end
Encoder.encoder_list.reject! { |_source_id, v| v.hostname.nil? }

if ARGV.empty?
  current_status
  assign_action
  Kernel.const_get("Action#{action_class}").new
else
  source_id = ARGV[0].to_s.upcase
  action = ARGV[1].to_s.downcase

  raise('Invalid Source ID Entered') unless GlobalVariables.ou_service_list.any? { |i| i == source_id }

  GlobalVariables.target_source_id = source_id
  selected_input = if source_id == 'M2005'
                     'M2005_NFLNAL1_NFL_SES_PRI'
                   else
                     'M2015_NFLNAL3_NFL_SES_PRI'
                   end

  Zixi.zixi_pri.selected_input = selected_input
  Zixi.zixi_pri.selected_output = source_id
  Zixi.zixi_bck.selected_input = selected_input.gsub('_PRI', '_BCK')
  Zixi.zixi_bck.selected_output = source_id

  unaccompanied_action_sequence(action)
end
