# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'
require 'colored'

def env_has_key(key)
  ENV[key].nil? || ENV[key].empty? ? abort("Missing #{key}.".red) : ENV[key]
end

def get_env_variable(key)
  ENV[key].nil? || ENV[key].empty? ? nil : ENV[key]
end

MINUTES_IN_A_DAY = 1440
$file = env_has_key('AC_TESTINIUM_APP_PATH')
$file_name = File.basename($file).to_s
$extension = File.extname($file_name)
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$project_id = env_has_key('AC_TESTINIUM_PROJECT_ID')
$company_id = get_env_variable('AC_TESTINIUM_COMPANY_ID')
$env_file_path = env_has_key('AC_ENV_FILE_PATH')
$each_api_max_retry_count = env_has_key('AC_TESTINIUM_MAX_API_RETRY_COUNT').to_i
$end_time = DateTime.now + Rational(env_has_key('AC_TESTINIUM_TIMEOUT').to_i, MINUTES_IN_A_DAY)
$cloud_base_url = "https://testinium.io/"
$ent_base_url = get_env_variable('AC_TESTINIUM_ENTERPRISE_BASE_URL')

def get_base_url
  URI.join($ent_base_url || $cloud_base_url, "Testinium.RestApi/api").to_s
end

def get_parsed_response(response)
  JSON.parse(response, symbolize_names: true)
rescue JSON::ParserError, TypeError => e
  puts "\nJSON expected but received: #{response}".red
  abort "Error Message: #{e}".red
end

def check_timeout
  if DateTime.now > $end_time
    abort "Timeout exceeded! Increase AC_TESTINIUM_TIMEOUT if needed.".red
  end
end

def retry_request(max_retries)
  count = 1
  while count <= max_retries
    check_timeout
    yield(count)
    count += 1
  end
  abort "Max retries exceeded.".red
end

def send_request(method, url, headers, body = nil)
  use_ssl = get_base_url.match?(/^https/)
  uri = URI.parse(url)
  req = case method.upcase
        when 'GET'
          Net::HTTP::Get.new(uri.request_uri, headers)
        when 'POST'
          post_req = Net::HTTP::Post.new(uri.request_uri, headers)
          if body.is_a?(Hash) && body.values.any? { |v| v.is_a?(File) }
            post_req.set_form(body, 'multipart/form-data')
          else
            post_req.set_form_data(body) if body
          end
          post_req
        when 'PUT'
          put_req = Net::HTTP::Put.new(uri.request_uri, headers)
          put_req.body = body.to_json if body
          put_req
        else
          raise "Unsupported HTTP method: #{method}"
        end

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: use_ssl) { |http| http.request(req) }
end

def handle_api_response(res, action, parsed = true)
  case res
  when Net::HTTPSuccess
    puts "#{action.capitalize} successful.".green
    return parsed ? get_parsed_response(res.body) : nil
  when Net::HTTPUnauthorized
    puts "Authorization error while #{action}: #{get_parsed_response(res.body)[:error_description]}".red
  when Net::HTTPClientError
    puts "Client error while #{action}: #{get_parsed_response(res.body)[:message]}".red
  else
    puts "Unexpected error while #{action}: #{get_parsed_response(res.body)}".red
  end
  return nil
end

def login
  puts "Logging in to Testinium...".yellow
  base_url = $ent_base_url ? get_base_url.sub("/api", "") : "https://account.testinium.com/uaa"

  # Testinium's login API uses a public generic token for authentication. More details:  
  # Cloud: https://testinium.gitbook.io/testinium/apis/auth/login  
  # Enterprise: https://testinium.gitbook.io/testinium-enterprise/apis/auth/login 
  token = $ent_base_url ? "Y2xpZW50MTpjbGllbnQx" : "dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5"
  url = "#{base_url}/oauth/token"
  headers = { 'Content-Type' => 'application/x-www-form-urlencoded', 'Authorization' => "Basic #{token}" }
  body = { 'grant_type' => 'password', 'username' => $username, 'password' => $password }

  retry_request($each_api_max_retry_count) do
    res = send_request('POST', url, headers, body)
    parsed_response = handle_api_response(res, "logging")
    return parsed_response[:access_token] if parsed_response
  end
end

def find_project(access_token)
  puts "Searching for project #{$project_id}...".blue
  url = "#{get_base_url}/projects/#{$project_id}"
  headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id }

  retry_request($each_api_max_retry_count) do
    res = send_request('GET', url, headers)
    parsed_response = handle_api_response(res, "searching the project")
    return parsed_response if parsed_response
  end
end

def upload(access_token)
  puts "Uploading #{$file_name} to Testinium...".yellow
  url = $ent_base_url ? "#{get_base_url}/file/project/#{$project_id}" : "#{get_base_url}/file/upload"
  file_form = $ent_base_url ? "files" : "file"
  headers = { 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id }
  form_data = { file_form => File.open($file), 'isSignRequired' => 'true' }

  retry_request($each_api_max_retry_count) do |count|
    puts "File upload attempt: #{count}".blue
    res = send_request('POST', url, headers, form_data)
    parsed_response = handle_api_response(res, "uploading the application", !$ent_base_url)
    return parsed_response if parsed_response
  end
end

def update_project(project, file_response, access_token)
  puts "Starting update project...".blue
  file_token = file_response[:file_token]
  abort('Upload error: File token missing.'.red) if file_token.nil?
  ios_meta = file_response[:meta_data]

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
    dict[:ios_mobile_app] = $file_name
    dict[:ios_app_hash] = project[:ios_app_hash]
    dict[:ios_file_token] = file_token
    dict[:ios_meta] = ios_meta
  when '.apk'
    puts "Android app uploading...".blue
    dict[:android_mobile_app] = $file_name
    dict[:android_file_token] = file_token
  else
    abort 'Error: Only .apk and .ipa files are supported.'.red
  end

  url = "https://testinium.io/Testinium.RestApi/api/projects/#{project[:id]}"
  headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" }

  retry_request($each_api_max_retry_count) do
    res = send_request('PUT', url, headers, dict)
    parsed_response = handle_api_response(res, "updating the project")
    return if parsed_response
  end
end

def fetch_app_id(access_token)
  puts "Fetching the uploaded application ID...".blue
  operating_system = { '.ipa' => 'Ios', '.apk' => 'Android' }[$extension] or abort 'Error: Only .apk and .ipa files are supported.'.red
  puts "Operating system is #{operating_system}.".blue

  project_data = find_project(access_token)
  mobile_apps = project_data[:mobile_apps]

  filtered_apps = mobile_apps.select { |app| app[:operating_system].casecmp?(operating_system.upcase) }
  latest_app = filtered_apps.max_by { |app| app[:created_at] }

  latest_app || (puts "No mobile apps found for OS: #{os}".red; nil)
  app_id = latest_app[:id]
  puts "Found latest #{latest_app[:operating_system]} app: ID=#{app_id}, Name=#{latest_app[:mobile_app_name]}".green

  open($env_file_path, 'a') { |f|
    f.puts "AC_TESTINIUM_UPLOADED_APP_ID=#{app_id}"
    f.puts "AC_TESTINIUM_APP_OS=#{operating_system}"
  }
end

access_token = login()
project = find_project(access_token)
file_response = upload(access_token)
$ent_base_url ? fetch_app_id(access_token) : update_project(project, file_response, access_token)