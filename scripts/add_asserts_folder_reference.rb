#!/usr/bin/env ruby

require 'pathname'

# 项目路径
project_path = File.expand_path('../ItemManager.xcodeproj/project.pbxproj', __dir__)

# 读取项目文件
content = File.read(project_path)

# 检查是否已经添加了 asserts 文件夹引用
if content.include?('asserts */ = {isa = PBXFileReference') || content.include?('path = asserts; sourceTree = "<group>"')
  puts "Asserts folder reference already exists. Skipping."
  exit 0
end

puts "Adding asserts folder reference to Xcode project..."

# 生成唯一的 UUID
def generate_uuid
  hex = (0...24).map { rand(16).to_s(16).upcase }.join
  hex[0..7] + hex[8..11] + hex[12..15] + hex[16..19] + hex[20..23]
end

file_ref_uuid = generate_uuid
build_file_uuid = generate_uuid

# 创建 PBXFileReference（文件夹引用）
file_ref = <<-REF
		#{file_ref_uuid} /* asserts */ = {isa = PBXFileReference; lastKnownFileType = folder; path = asserts; sourceTree = "<group>"; };
REF

# 创建 PBXBuildFile
build_file = <<-BUILD
		#{build_file_uuid} /* asserts in Resources */ = {isa = PBXBuildFile; fileRef = #{file_ref_uuid} /* asserts */; };
BUILD

# 在 PBXFileReference section 末尾添加
content.gsub!(/(\/\* End PBXFileReference section \*\/)/, "#{file_ref}/* End PBXFileReference section */")

# 在 PBXBuildFile section 末尾添加
content.gsub!(/(\/\* End PBXBuildFile section \*\/)/, "#{build_file}/* End PBXBuildFile section */")

# 在 Resources build phase 中添加文件夹引用
# 找到 Resources build phase 并在现有文件后添加
content.gsub!(
  /(A2AE58712F19377500B4B6EB \/\* Resources \*\/ = \{[\s\S]*?files = \(\s*)(A226CD742F26A507004E4E41 \/\* .*?logo.*?Resources \*\/)(\s*;)/,
  "\\1\\2,\n\t\t\t#{build_file_uuid} /* asserts in Resources */\\3"
)

# 在 mainGroup 中添加文件夹引用
# 找到 mainGroup 的 children 并添加
content.gsub!(
  /(A2AE586A2F19377500B4B6EB \/\* mainGroup \*\/ = \{[\s\S]*?children = \(\s*)(A2AE58742F19377500B4B6EB \/\* Products \*\/)(\s*;)/,
  "\\1\\2,\n\t\t\t#{file_ref_uuid} /* asserts */\\3"
)

# 写入文件
File.write(project_path, content)

puts "Successfully added asserts folder reference to Xcode project."
puts "UUID: #{file_ref_uuid}"
puts ""
puts "IMPORTANT: You need to:"
puts "1. Create a symbolic link or copy the asserts folder to the project root"
puts "2. Reload the project in Xcode"
puts "3. Build and run"
