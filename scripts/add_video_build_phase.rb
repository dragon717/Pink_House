#!/usr/bin/env ruby

require 'pathname'

# 项目路径
project_path = File.expand_path('../ItemManager.xcodeproj/project.pbxproj', __dir__)

# 读取项目文件
content = File.read(project_path)

# 生成唯一的 UUID
def generate_uuid
  hex = (0...24).map { rand(16).to_s(16).upcase }.join
  hex[0..7] + hex[8..11] + hex[12..15] + hex[16..19] + hex[20..23]
end

# 检查是否已经存在视频复制脚本
if content.include?('Copy Videos to Bundle')
  puts "Build phase 'Copy Videos to Bundle' already exists. Skipping."
  exit 0
end

# 生成新的 UUIDs
script_phase_uuid = generate_uuid

# 创建 Shell Script Build Phase 的内容
script_phase = <<~PHASE
/* Begin PBXShellScriptBuildPhase section */
		#{script_phase_uuid} /* Copy Videos to Bundle */ = {
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
			);
			name = "Copy Videos to Bundle";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "#{File.expand_path('copy_videos_to_bundle.sh', __dir__).gsub(/\//, '/')}";
		};
/* End PBXShellScriptBuildPhase section */

PHASE

# 在 /* Begin PBXShellScriptBuildPhase section */ 之前插入（如果不存在则创建）
if content.include?('/* Begin PBXShellScriptBuildPhase section */')
  # 在现有的 PBXShellScriptBuildPhase section 中添加
  content.gsub!(/\/\* Begin PBXShellScriptBuildPhase section \*\//, "/* Begin PBXShellScriptBuildPhase section */\n#{script_phase.chomp}")
else
  # 在 /* Begin PBXSourcesBuildPhase section */ 之前插入新的 section
  content.gsub!(/(\/\* Begin PBXSourcesBuildPhase section \*\/)/, "#{script_phase}\\1")
end

# 在 ItemManager target 的 buildPhases 中添加引用
# 找到 ItemManager target 的 buildPhases 并在 Resources 之后添加
content.gsub!(
  /(A2AE58722F19377500B4B6EB \/\* ItemManager \*\/ = \{\s*isa = PBXNativeTarget;[\s\S]*?buildPhases = \(\s*A2AE586F2F19377500B4B6EB \/\* Sources \*\/\s*,\s*A2AE58702F19377500B4B6EB \/\* Frameworks \*\/\s*,\s*A2AE58712F19377500B4B6EB \/\* Resources \*\/)(\s*,)/,
  "\\1,\n\t\t\t#{script_phase_uuid} /* Copy Videos to Bundle */\\2"
)

# 写入文件
File.write(project_path, content)

puts "Successfully added 'Copy Videos to Bundle' build phase to project."
puts "UUID: #{script_phase_uuid}"
