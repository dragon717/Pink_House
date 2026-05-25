#!/usr/bin/env ruby
# frozen_string_literal: true
#
# materialize_manual_image2_assets.rb
#
# Take user-supplied image2 PNGs from <theme_dir>/_artifacts/generated/image2_manual/
# and write them into ItemManager/Assets.xcassets/ThemeSkin/<namespace>/<name>.imageset/
# as @2x + @3x + Contents.json.
#
# Engineering contract:
#   - Idempotent: existing imageset files are NEVER overwritten unless --force.
#   - Dry-run: --dry-run lists expected / missing / meta / placeholder /
#     would-write, exits 1 if any preflight gate fails.
#   - Source-type guard: PSD themes may dry-run for enumeration, but writing
#     needs --allow-psd-fallback.
#   - Can run from repo root; PROJ env overrides Dir.pwd when set.
#   - Reads tools/theme_skin/theme_manifest.yaml by default; --manifest-path
#     and THEME_SKIN_MANIFEST_PATH can point at another manifest when needed.
#   - sips required (macOS only). On Linux/CI fail loud.
#   - Contents.json uses string keys exclusively (no Ruby symbols mixed in).
#   - Contents.json carries a top-level comment field for source audit:
#     "source: image2_manual; pipeline: ...".
#   - 9-slice center is computed from actual image dimensions, never hardcoded.
#   - MISSING output is classified by pipeline (common/sticker/extras) so users
#     know which path each missing PNG should come from.
#
# Usage:
#
# Options:
#   --theme-id THEME_ID       Theme id; defaults to THEME_ID env.
#   --manifest-path PATH      Manifest path; defaults to tools/theme_skin/theme_manifest.yaml.
#   --dry-run                 Don't write anything; report what would happen.
#   --force                   Overwrite existing imageset files.
#   --allow-psd-fallback      Required to write source_type=psd themes.
#   -h / --help               Print usage.

require 'yaml'
require 'json'
require 'fileutils'
require 'open3'
require 'optparse'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# ---------- options ----------

options = {
  dry_run: false,
  force: false,
  allow_psd_fallback: false,
  theme_id: nil,
  manifest_path: nil
}

DEFAULT_MANIFEST_RELATIVE_PATH = 'tools/theme_skin/theme_manifest.yaml'

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id THEME_ID [options]'
  opts.on('--theme-id THEME_ID', 'Theme id; defaults to THEME_ID env') { |v| options[:theme_id] = v }
  opts.on('--manifest-path PATH', "Manifest path; defaults to #{DEFAULT_MANIFEST_RELATIVE_PATH}") { |v| options[:manifest_path] = v }
  opts.on('--dry-run', 'List expected/missing/would-write, no file ops') { options[:dry_run] = true }
  opts.on('--force',   'Overwrite existing imageset files')              { options[:force] = true }
  opts.on('--allow-psd-fallback', 'Allow running on PSD-source themes')  { options[:allow_psd_fallback] = true }
  opts.on('-h', '--help', 'Show help') { puts opts; exit 0 }
end.parse!

# ---------- env contract ----------

root = ENV['PROJ']&.dup&.force_encoding('UTF-8')
root = Dir.pwd if root.nil? || root.empty?
abort 'ERROR: run from repo root or set PROJ (see docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md)' unless root && !root.empty?
abort "ERROR: PROJ does not exist: #{root}" unless File.directory?(root)
abort "ERROR: repo root not recognized: #{root}" unless File.file?(File.join(root, 'ItemManager.xcodeproj/project.pbxproj'))

theme_id = (options[:theme_id] || ENV['THEME_ID'])&.dup&.force_encoding('UTF-8')
abort 'ERROR: THEME_ID required (pass --theme-id or set THEME_ID env)' unless theme_id && !theme_id.empty?

# ---------- dependency check ----------

unless system('which sips > /dev/null 2>&1')
  abort 'ERROR: `sips` not found on PATH. This script is macOS-only (sips ships with macOS).'
end

# ---------- manifest load ----------

manifest_path = options[:manifest_path] || ENV['THEME_SKIN_MANIFEST_PATH'] || File.join(root, DEFAULT_MANIFEST_RELATIVE_PATH)
manifest_path = File.join(root, manifest_path) unless manifest_path.start_with?('/')
abort "ERROR: manifest not found: #{manifest_path}" unless File.file?(manifest_path)
manifest = YAML.load_file(manifest_path)

theme = manifest.fetch('themes').find { |item| item.fetch('theme_id') == theme_id }
abort "ERROR: theme not found in manifest: #{theme_id}" unless theme

namespace   = theme.fetch('namespace')
theme_dir   = theme.fetch('theme_dir')
source_type = theme.fetch('source_type')

# ---------- source-type guard ----------

if source_type == 'psd' && !options[:allow_psd_fallback] && !options[:dry_run]
  abort <<~MSG
    ERROR: theme #{theme_id} has source_type=psd; the manual image2 fallback path is
    designed for jpg-source themes (sticker_bbox + image2 補缺). PSD themes should
    export layers via psd-tools first. If you really want to run this script on a PSD
    theme, pass --allow-psd-fallback explicitly.
  MSG
end

# ---------- collect expected imageset names + classify ----------

common_groups = manifest.fetch('shared').fetch('imageset_common')
common_names  = common_groups.values.flatten
extras_names  = theme['imageset_extras'] || []
sticker_names = (theme['sticker_bbox'] || {}).keys

# Classification: name -> pipeline tag for MISSING output
classify = {}
common_pipeline = source_type == 'psd' ? 'common[psd_layer→image2]' : 'common[image2]'
common_names.each  { |n| classify[n] ||= common_pipeline }
extras_names.each do |n|
  classify[n] ||= if source_type == 'psd'
                    mapped = (theme['layer_map'] || {})[n].to_s
                    mapped.start_with?('png:') ? 'extras[png_pre_extracted]' : 'extras[psd_layer→image2]'
                  else
                    'extras[image2]'
                  end
end
sticker_names.each { |n| classify[n] ||= 'sticker[rembg→image2]' }
names = (common_names + extras_names + sticker_names).uniq

# ---------- 9-slice cap-insets table (top, left, bottom, right) ----------

CAP_INSETS = {
  'top_bar_main_default'         => { 'top' => 40, 'left' => 60, 'bottom' => 40, 'right' => 60 },
  'tab_bar_main_default'         => { 'top' => 80, 'left' => 90, 'bottom' => 80, 'right' => 90 },
  'search_bar_compact_default'   => { 'top' => 30, 'left' => 60, 'bottom' => 30, 'right' => 60 },
  'card_wardrobe_item_default'   => { 'top' => 80, 'left' => 80, 'bottom' => 80, 'right' => 80 },
  'card_stats_default'           => { 'top' => 30, 'left' => 30, 'bottom' => 30, 'right' => 30 },
  'card_stats_pink'              => { 'top' => 30, 'left' => 30, 'bottom' => 30, 'right' => 30 },
  'card_stats_blue'              => { 'top' => 30, 'left' => 30, 'bottom' => 30, 'right' => 30 },
  'card_stats_purple'            => { 'top' => 30, 'left' => 30, 'bottom' => 30, 'right' => 30 },
  'card_settings_grid_default'   => { 'top' => 24, 'left' => 24, 'bottom' => 24, 'right' => 24 }
}.freeze

# Minimum @3x source pixel size per imageset (warns on user-supplied PNG too small)
MIN_SIZE = {
  'top_bar_main_default'       => [1206, 220],
  'tab_bar_main_default'       => [1206, 300],
  'wallpaper_main'             => [1206, 2622],
  'preview_store_hero'         => [768, 1376],
  'card_wardrobe_item_default' => [600, 800]
}.freeze

# Transparent placeholders / empty PNGs are usually far below this threshold.
# Keep this as a hard preflight failure so empty imagesets cannot bypass SwiftUI
# programmatic fallback and accidentally pass visual-only acceptance.
MIN_SOURCE_BYTES = 2048

# ---------- source resolution ----------

manual_dir = File.join(root, theme_dir, '_artifacts/generated/image2_manual')
asset_root = File.join(root, 'ItemManager/Assets.xcassets/ThemeSkin', namespace)

layer_map = theme['layer_map'] || {}

source_info_for = lambda do |name|
  manual = File.join(manual_dir, "#{name}.png")
  if File.exist?(manual)
    return {
      'path' => manual,
      'source' => 'image2_manual',
      'meta_path' => File.join(manual_dir, "#{name}.meta.json")
    }
  end

  # PSD 主题：layer_map 里 "png:<rel>" 表示该 imageset 的源已经在 ${THEME_DIR}/<rel> 预导出
  # （走 Photoshop 切片 → TIFF → convert_tiff_to_png.py → png/*.png 的离线流程）。
  mapped = layer_map[name].to_s
  if mapped.start_with?('png:')
    rel = mapped.sub(/\Apng:/, '')
    candidate = File.join(root, theme_dir, rel)
    return { 'path' => candidate, 'source' => 'png_pre_extracted', 'meta_path' => nil } if File.exist?(candidate)
  end

  if name == 'preview_store_hero'
    src = theme['preview_hero_src']
    if src && !src.start_with?('__EXPORT__/')
      candidate = File.join(root, theme_dir, src)
      return { 'path' => candidate, 'source' => 'preview_source', 'meta_path' => nil } if File.exist?(candidate)
    end
  end

  nil
end

source_for = lambda { |name| source_info_for.call(name)&.fetch('path') }

complete_imageset = lambda do |out_dir, name|
  File.exist?(File.join(out_dir, 'Contents.json')) &&
    File.exist?(File.join(out_dir, "#{name}@2x.png")) &&
    File.exist?(File.join(out_dir, "#{name}@3x.png"))
end

valid_meta = lambda do |name, meta_path|
  return true if meta_path.nil?
  return false unless File.file?(meta_path)

  data = JSON.parse(File.read(meta_path, encoding: 'UTF-8'))
  data.is_a?(Hash) &&
    data['name'] == name &&
    %w[source prompt model mode].any? { |key| data.key?(key) && !data[key].to_s.empty? }
rescue JSON::ParserError
  false
end

# ---------- pre-flight report ----------

missing = []
missing_meta = []
placeholder_suspects = []
would_skip  = []
would_write = []

names.each do |name|
  out_dir   = File.join(asset_root, "#{name}.imageset")
  if !options[:force] && complete_imageset.call(out_dir, name)
    png3x = File.join(out_dir, "#{name}@3x.png")
    bytes = File.size(png3x)
    placeholder_suspects << [name, bytes, 'existing @3x'] if bytes < MIN_SOURCE_BYTES
    would_skip << name
    next
  end

  info = source_info_for.call(name)
  if info.nil?
    missing << name
    next
  end
  missing_meta << name unless valid_meta.call(name, info['meta_path'])
  bytes = File.size(info['path'])
  placeholder_suspects << [name, bytes, 'source'] if bytes < MIN_SOURCE_BYTES
  would_write << name
end

puts "THEME_ID=#{theme_id}"
puts "namespace=#{namespace}"
puts "source_type=#{source_type}"
puts "manifest_path=#{manifest_path}"
puts "manual_dir=#{manual_dir}"
puts "asset_root=#{asset_root}"
puts "expected=#{names.size}  missing=#{missing.size}  missing_meta=#{missing_meta.size}  placeholder_suspect=#{placeholder_suspects.size}  would_write=#{would_write.size}  would_skip=#{would_skip.size}"

if missing.any?
  missing.sort_by { |n| classify[n] }.each do |n|
    puts "MISSING [#{classify[n]}] #{n}.png"
  end
end
missing_meta.sort.each { |n| puts "MISSING-META #{n}.meta.json (required for image2_manual source audit)" }
placeholder_suspects.sort.each do |name, bytes, where|
  puts "PLACEHOLDER-SUSPECT #{name}.png (#{where}: #{bytes} bytes < #{MIN_SOURCE_BYTES}; likely transparent/empty placeholder)"
end

if options[:dry_run]
  puts '---'
  puts 'dry-run: no files written'
  would_write.each { |n| puts "WOULD-WRITE #{n}.imageset" }
  would_skip.each  { |n| puts "WOULD-SKIP  #{n}.imageset (already populated; use --force to overwrite)" }
  exit(missing.any? || missing_meta.any? || placeholder_suspects.any? ? 1 : 0)
end

abort 'manual image2 assets are incomplete; resolve MISSING list before re-running without --dry-run' if missing.any?
abort 'manual image2 source audit is incomplete; add/fix .meta.json before re-running' if missing_meta.any?
abort 'placeholder-suspect PNG detected; replace tiny/transparent placeholder before re-running' if placeholder_suspects.any?

# ---------- write namespace folder Contents.json (string keys throughout) ----------

FileUtils.mkdir_p(asset_root)
namespace_contents = {
  'info'       => { 'version' => 1, 'author' => 'xcode' },
  'properties' => { 'provides-namespace' => false }
}
namespace_contents_path = File.join(asset_root, 'Contents.json')
if options[:force] || !File.exist?(namespace_contents_path)
  File.write(namespace_contents_path, JSON.pretty_generate(namespace_contents) + "\n")
else
  puts 'SKIP  namespace Contents.json (exists; --force to overwrite)'
end

# ---------- helpers ----------

pixel_size = lambda do |path|
  stdout, stderr, status = Open3.capture3('sips', '-g', 'pixelWidth', '-g', 'pixelHeight', path)
  abort "sips failed for #{path}: #{stderr}" unless status.success?
  width  = stdout[/pixelWidth:\s*(\d+)/, 1].to_i
  height = stdout[/pixelHeight:\s*(\d+)/, 1].to_i
  abort "could not read pixel size for #{path}" if width <= 0 || height <= 0
  [width, height]
end

# ---------- per-imageset write ----------

written = 0
skipped = 0

names.each do |name|
  out_dir  = File.join(asset_root, "#{name}.imageset")
  contents_path = File.join(out_dir, 'Contents.json')
  out3     = File.join(out_dir, "#{name}@3x.png")
  out2     = File.join(out_dir, "#{name}@2x.png")

  if !options[:force] && complete_imageset.call(out_dir, name)
    puts "SKIP  #{name}.imageset (exists; --force to overwrite)"
    skipped += 1
    next
  end

  info     = source_info_for.call(name)
  src      = info.fetch('path')

  FileUtils.mkdir_p(out_dir)
  width, height = pixel_size.call(src)

  if (min = MIN_SIZE[name])
    if width < min[0] || height < min[1]
      warn "WARN  #{name}.png is #{width}x#{height}; recommended ≥ #{min[0]}x#{min[1]} (continuing)"
    end
  end

  FileUtils.cp(src, out3)

  width2  = [(width  * 2.0 / 3.0).round, 1].max
  height2 = [(height * 2.0 / 3.0).round, 1].max
  _stdout, stderr, status = Open3.capture3('sips', '-z', height2.to_s, width2.to_s, src, '--out', out2)
  abort "sips resize failed for #{src}: #{stderr}" unless status.success?

  contents = {
    'comment' => "source: #{info.fetch('source')}; pipeline: #{classify[name]}",
    'info'   => { 'version' => 1, 'author' => 'xcode' },
    'images' => [
      { 'idiom' => 'universal', 'scale' => '2x', 'filename' => "#{name}@2x.png" },
      { 'idiom' => 'universal', 'scale' => '3x', 'filename' => "#{name}@3x.png" }
    ]
  }

  if (ci = CAP_INSETS[name])
    # Use @2x dimensions for cap-insets/center math; cap-insets are in pixels
    # relative to the 1x rendering, but 9-slice center must be > 0 in both dims.
    cw = [width2 - ci['left']   - ci['right'],  1].max
    ch = [height2 - ci['top']   - ci['bottom'], 1].max
    contents['properties'] = {
      'resizing' => {
        'mode'       => '9-part',
        'center'     => { 'mode' => 'stretch', 'width' => cw, 'height' => ch },
        'cap-insets' => ci
      }
    }
  end

  File.write(contents_path, JSON.pretty_generate(contents) + "\n")
  puts "WROTE #{name}.imageset"
  written += 1
end

puts '---'
puts "summary: written=#{written}  skipped=#{skipped}  total=#{names.size}"
