require 'yaml'
require 'open3'
require 'find'
require 'fileutils'
require 'json'

def get_env_variable(key)
	return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end

android_home = get_env_variable("ANDROID_HOME") || abort('Missing ANDROID_HOME variable.')
ac_build_output_path = get_env_variable("AC_OUTPUT_DIR") || abort('Missing AC_OUTPUT_DIR variable.')

$latest_build_tools = Dir.glob("#{android_home}/build-tools/*").sort.last
apks = Dir.glob("#{ac_build_output_path}/**/*.apk")
aabs = Dir.glob("#{ac_build_output_path}/**/*.aab")

def run_command(command)
    puts "@[command] #{command}"
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

def is_signed(meta_files) 
    meta_files.each do |file| 
        if file.downcase.include?(".dsa") || file.downcase.include?(".rsa")
            return true
        end
    end
    return false
end

def filter_meta_files(path) 
    return run_command("#{$latest_build_tools}/aapt ls #{path} | grep META-INF").split("\n")
end

datas = []
apks.concat(aabs).each do |artifact_path|
    base_name = File.basename(artifact_path)
    meta_files = filter_meta_files(artifact_path)
    datas.push({
        "signed": is_signed(meta_files),
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