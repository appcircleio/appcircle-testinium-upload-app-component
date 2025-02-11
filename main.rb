# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.")
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
  puts "\nJSON was expected from the response of Testinium API, but the received value is: (#{response})\n. Error Message: #{e}\n"
  exit(1)
end

def check_timeout()
  puts "Checking timeout..."
  now = DateTime.now

  if(now > $end_time)
    puts 'The component is terminating due to a timeout exceeded.
     If you want to allow more time, please increase the AC_TESTINIUM_TIMEOUT input value.'
    exit(1)
  end
end

def is_count_less_than_max_api_retry(count)
  return count < $each_api_max_retry_count
end

def login()
  puts "Logging in to Testinium..."
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Signing in. Number of attempts: #{count}")

    req = Net::HTTP::Post.new(uri.request_uri,
                              { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
    req.set_form_data({ 'grant_type' => 'password', 'username' => $username, 'password' => $password })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Successfully logged in...')
      return get_parsed_response(res.body)[:access_token]
    elsif (res.kind_of? Net::HTTPUnauthorized)
      puts(get_parsed_response(res.body)[:error_description])
      count += 1
    else
      puts("Error while signing in. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def find_project(access_token)
  count = 1
  puts("Starting to find the project...")

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Finding project. Number of attempts: #{count}")

    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{$project_id}")
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Project was found successfully...')
      return get_parsed_response(res.body)
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while finding project. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def upload(access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Uploading #{$file_name} to Testinium... Number of attempts: #{count}")

    uri = URI.parse('https://testinium.io/Testinium.RestApi/api/file/upload')
    req = Net::HTTP::Post.new(uri.request_uri,
                              { 'Accept' => '*/*', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    form_data = [
      ['file', File.open($file)],
      %w[isSignRequired true]
    ]
    req.set_form(form_data, 'multipart/form-data')
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('File uploaded successfully...')
      return get_parsed_response(res.body)
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while uploading File. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def update_project(project, file_response, access_token)
  count = 1

  file_token = file_response[:file_token]
  ios_meta = file_response[:meta_data]
  raise('Upload error. File token not found.') if file_token.nil?

  puts("File uploaded successfully #{file_token}")

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
    puts "iOS app uploading."
    dict[:ios_mobile_app] = $file_name_str
    dict[:ios_app_hash] = project[:ios_app_hash]
    dict[:ios_mobile_app] = $file_name_str
    dict[:ios_file_token] = file_token
    dict[:ios_meta] = ios_meta
  when '.apk'
    puts "Android app uploading."
    dict[:android_mobile_app] = $file_name_str
    dict[:android_file_token] = file_token
  else
    raise 'Error: Only can resign .apk files and .ipa files.'
  end

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Testinium project is updating... Number of attempts: #{count}")
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/projects/#{project[:id]}")
    req = Net::HTTP::Put.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    req.body = JSON.dump(dict)
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Project updated successfully...')
      return get_parsed_response(res.body)
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while updating Project. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end


access_token = login()
project = find_project(access_token)
file_response = upload(access_token)
update_project(project, file_response, access_token)