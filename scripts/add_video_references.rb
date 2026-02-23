#!/usr/bin/env ruby

require 'pathname'

# 项目路径
project_path = File.expand_path('../ItemManager.xcodeproj/project.pbxproj', __dir__)

# 读取项目文件
content = File.read(project_path)

# 视频目录
video_dirs = {
  'naicha' => File.expand_path('../ItemManager/asserts/naicha', __dir__),
  'maomao' => File.expand_path('../ItemManager/asserts/maomao', __dir__)
}

# 生成唯一的 UUID
def generate_uuid
  hex = (0...24).map { rand(16).to_s(16).upcase }.join
  hex[0..7] + hex[8..11] + hex[12..15] + hex[16..19] + hex[20..23]
end

# 检查是否已经添加了视频引用
if content.include?('naicha_idle.mov') || content.include?('/* Videos */')
  puts "Video references already exist. Skipping."
  exit 0
end

puts "Adding video file references to Xcode project..."

# 收集所有视频文件
video_files = []
video_dirs.each do |name, dir|
  next unless Dir.exist?(dir)
  
  Dir.glob(File.join(dir, '*.mov')).each do |file|
    video_files << {
      name: File.basename(file),
      path: "asserts/#{name}/#{File.basename(file)}",
      dir: name
    }
  end
end

puts "Found #{video_files.count} video files"

# 为每个视频文件创建 PBXFileReference
file_refs = []
build_files = []

video_files.each do |video|
  file_ref_uuid = generate_uuid
  build_file_uuid = generate_uuid
  
  # 创建 PBXFileReference
  file_ref = <<-REF
    #{file_ref_uuid} /* #{video[:name]} */ = {isa = PBXFileReference; lastKnownFileType = video; name = #{video[:name]}; path = #{video[:path]}; sourceTree = "<group>"; };
REF
  file_refs << file_ref.chomp
  
  # 创建 PBXBuildFile
  build_file = <<-BUILD
    #{build_file_uuid} /* #{video[:name]} in Resources */ = {isa = PBXBuildFile; fileRef = #{file_ref_uuid} /* #{video[:name]} */; };
BUILD
  build_files << build_file.chomp
end

# 在 PBXFileReference section 末尾添加视频引用
file_refs_section = file_refs.join("\n")
content.gsub!(/(\/\* End PBXFileReference section \*\/)/, "#{file_refs_section}\n/* End PBXFileReference section */")

# 在 PBXBuildFile section 末尾添加
build_files_section = build_files.join("\n")
content.gsub!(/(\/\* End PBXBuildFile section \*\/)/, "#{build_files_section}\n/* End PBXBuildFile section */")

# 在 Resources build phase 中添加视频文件
# 找到 Resources build phase 的 files 列表
resources_files = build_files.map do |bf|
  uuid = bf.match(/^(\w+)/)[1]
  name = bf.match(/\/\* (.+) in Resources/)[1]
  "#{uuid} /* #{name} in Resources */"
end

# 在 Resources build phase 中添加这些文件
# 找到 A2AE58712F19377500B4B6EB /* Resources */ 并添加文件
resources_section = resources_files.join(",\n\t\t\t")
content.gsub!(
  /(A2AE58712F19377500B4B6EB \/\* Resources \*\/ = \{\s*isa = PBXResourcesBuildPhase;[\s\S]*?files = \(\s*)(A226CD742F26A507004E4E41 \/\* .*?Resources \*\/)(\s*;)/,
  "\\1\\2,\n\t\t\t#{resources_section}\\3"
)

# 写入文件
File.write(project_path, content)

puts "Successfully added #{video_files.count} video file references to Xcode project."
puts "Please reload the project in Xcode and build again."
