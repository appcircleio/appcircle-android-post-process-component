require 'yaml'
require 'open3'
require 'find'
require 'fileutils'
require 'json'

def get_env_variable(key)
    return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end

def abort_with0(message)
    puts "@@[error] #{message}"
    exit 0
end

android_home = get_env_variable("ANDROID_HOME") || abort('Missing ANDROID_HOME variable.')
ac_build_output_path = get_env_variable("AC_OUTPUT_DIR") || abort('Missing AC_OUTPUT_DIR variable.')

$latest_build_tools = Dir.glob("#{android_home}/build-tools/*").sort.last
apks = Dir.glob("#{ac_build_output_path}/**/*.apk")
aabs = Dir.glob("#{ac_build_output_path}/**/*.aab")

def run_command(command)
    puts "@@[command] #{command}"
    status = nil
    stdout_str = nil
    stderr_str = nil

    Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
        stdout_str = stdout.read
        stderr_str = stderr.read
        status = wait_thr.value
        puts stdout_str
    end

    unless status.success?
        puts stderr_str
        raise stderr_str
    end
    return stdout_str
end

def is_signed(meta_files, path)
    v2_signed = false
    begin
        puts "Verifying APK signature for: #{path}"
        v2_signed = run_command("#{$latest_build_tools}/apksigner verify --verbose \"#{path}\" | head -1").include?('Verifies')
    rescue StandardError
        puts "Unable to verify v2 signature. Skipping v2 verification."
        v2_signed = false
    end
    return true if v2_signed

    puts "Scanning META-INF for DSA or RSA signature files..."
    meta_files.each do |file| 
        if file.downcase.include?(".dsa") || file.downcase.include?(".rsa")
            puts "DSA or RSA signature files found in META-INF. The app is signed."
            return true
        end
    end
    puts "No DSA or RSA signature files found in META-INF. The app is unsigned."
    return false
end

def filter_meta_files(path)
    is_aapt_success = true
    begin
        puts "Attempting to extract META-INF files using aapt for: #{path}"
        return run_command("#{$latest_build_tools}/aapt ls \"#{path}\" | grep META-INF").split("\n")
    rescue StandardError
        puts "aapt failed to open the file #{path}."
        is_aapt_success = false
    end

    if !is_aapt_success
        begin
            puts "Attempting to extract META-INF files using jarsigner for: #{path}"
            return run_command("jarsigner -verify -verbose \"#{path}\" | grep 'META-INF'").split("\n")
        rescue StandardError => e
            abort_with0("Both aapt and jarsigner failed to process #{path}. Error: #{e}.\n" \
                "Automatic distribution will not proceed as the signing status of the app cannot be confirmed.")
        end
    end
end

datas = []
apks.concat(aabs).each do |artifact_path|
    base_name = File.basename(artifact_path)
    meta_files = filter_meta_files(artifact_path)
    signed = is_signed(meta_files, artifact_path)
    datas.push({
        "signed": signed,
        "app_name": base_name
    })
end

post_process_output_file_path = "#{ac_build_output_path}/ac_post_process_output.json"
File.open(post_process_output_file_path, "w") do |f|
    f.write(datas.to_json)
end
  
# Write Environment Variable
open(ENV['AC_ENV_FILE_PATH'], 'a') { |f|
    f.puts "AC_ANDROID_POST_PROCESS_OUTPUT_PATH=#{post_process_output_file_path}"
}

exit 0