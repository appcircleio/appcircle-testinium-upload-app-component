# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'
require 'colored'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.".red)
end

MINUTES_IN_A_DAY = 1440
file = env_has_key('AC_TESTINIUM_APP_PATH')
$file = file
$file_name = File.basename(file)
$file_name_str = $file_name.to_s
$extension = File.extname($file_name)
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$project_id = env_has_key('AC_TESTINIUM_PROJECT_ID')
$company_id = env_has_key('AC_TESTINIUM_COMPANY_ID')
$each_api_max_retry_count = env_has_key('AC_TESTINIUM_MAX_API_RETRY_COUNT').to_i
timeout = env_has_key('AC_TESTINIUM_TIMEOUT').to_i
date_now = DateTime.now
$end_time = date_now + Rational(timeout, MINUTES_IN_A_DAY)
$time_period = 30

def get_parsed_response(response)
  JSON.parse(response, symbolize_names: true)
rescue JSON::ParserError, TypeError => e
  puts "\nJSON expected but received: #{response}".red
  puts "Error Message: #{e}".red
  exit(1)
end

def check_timeout()
  puts "Checking timeout...".yellow
  now = DateTime.now

  if now > $end_time
    puts "Timeout exceeded! If you want to allow more time, please increase the AC_TESTINIUM_TIMEOUT input value.".red
    exit(1)
  end
end

def is_count_less_than_max_api_retry(count)
  return count < $each_api_max_retry_count
end

def login()
  puts "Logging in to Testinium...".yellow
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  count = 1

  while is_count_less_than_max_api_retry(count)
    check_timeout()
    puts "Signing in. Attempt: #{count}".blue

    req = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
    req.set_form_data({ 'grant_type' => 'password', 'username' => $username, 'password' => $password })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "Successfully logged in...".green
      return get_parsed_response(res.body)[:access_token]
    elsif res.is_a?(Net::HTTPUnauthorized)
      puts get_parsed_response(res.body)[:error_description].red
      count += 1
    else
      puts "Login error: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

def find_project(access_token)
  count = 1
  puts "Searching for project...".blue

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts "Finding project. Attempt: #{count}".yellow

    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{$project_id}")
    req = Net::HTTP::Get.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "Project found successfully!".green
      return get_parsed_response(res.body)
    elsif res.is_a?(Net::HTTPClientError)
      puts get_parsed_response(res.body)[:message].red
      count += 1
    else
      puts "Project search error! Server response: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

def upload(access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts "Uploading #{$file_name} to Testinium... Attempt: #{count}".yellow

    uri = URI.parse('https://testinium.io/Testinium.RestApi/api/file/upload')
    req = Net::HTTP::Post.new(uri.request_uri, { 'Accept' => '*/*', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    form_data = [['file', File.open($file)], %w[isSignRequired true]]
    req.set_form(form_data, 'multipart/form-data')
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "File uploaded successfully!".green
      return get_parsed_response(res.body)
    elsif res.is_a?(Net::HTTPClientError)
      puts get_parsed_response(res.body)[:message].red
      count += 1
    else
      puts "File upload error! Server response: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

def update_project(project, file_response, access_token)
  count = 1
  file_token = file_response[:file_token]
  ios_meta = file_response[:meta_data]
  abort('Upload error: File token missing.'.red) if file_token.nil?

  puts "File uploaded successfully #{file_token}".green

  dict = {
    'enabled' => true,
    'test_framework' => project[:test_framework],
    'test_runner_tool' => project[:test_runner_tool],
    'repository_path' => project[:repository_path],
    'test_file_type' => project[:test_file_type],
    'project_name' => project[:project_name]
  }

  case $extension
  when '.ipa'
    puts "iOS app uploading...".blue
    dict[:ios_mobile_app] = $file_name_str
    dict[:ios_app_hash] = project[:ios_app_hash]
    dict[:ios_file_token] = file_token
    dict[:ios_meta] = ios_meta
  when '.apk'
    puts "Android app uploading...".blue
    dict[:android_mobile_app] = $file_name_str
    dict[:android_file_token] = file_token
  else
    abort 'Error: Only .apk and .ipa files are supported.'.red
  end

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts "Updating Testinium project... Attempt: #{count}".yellow

    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{project[:id]}")
    req = Net::HTTP::Put.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    req.body = JSON.dump(dict)
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "Project updated successfully!".green
      return get_parsed_response(res.body)
    elsif res.is_a?(Net::HTTPClientError)
      puts get_parsed_response(res.body)[:message].red
      count += 1
    else
      puts "Project update error! Server response: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

access_token = login()
project = find_project(access_token)
file_response = upload(access_token)
update_project(project, file_response, access_token)