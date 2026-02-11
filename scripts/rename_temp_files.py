import os
import glob

def rename_files():
    base_dir = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/temp"
    
    # 映射规则：关键词 -> 新的基础名称
    # 注意：关键词需要足够独特以区分文件
    rules = [
        ("启动 (Start)", "cat_rush_start_loop"),
        ("基础待机 (Idle Loop)", "cat_idle_loop"),
        ("打完工累瘫", "cat_work_exhausted"),
        ("登基仪式系列", "cat_coronation"),
        ("打工成功", "cat_work_success")
    ]
    
    files = glob.glob(os.path.join(base_dir, "*"))
    
    for file_path in files:
        filename = os.path.basename(file_path)
        
        # 跳过已重命名的文件 (简单的判断：如果不包含中文且比较短，可能已经处理过，或者不符合长文件名特征)
        # 这里主要匹配规则
        
        new_base_name = None
        for keyword, name in rules:
            if keyword in filename:
                new_base_name = name
                break
        
        if new_base_name:
            # 保持后缀和可能的 _video/_audio 标记
            # 检查是否有 _video 或 _audio
            suffix = ""
            ext = os.path.splitext(filename)[1]
            
            # 移除扩展名后的文件名主体
            name_body = os.path.splitext(filename)[0]
            
            if name_body.endswith("_video"):
                suffix = "_video"
            elif name_body.endswith("_audio"):
                suffix = "_audio"
            elif "_clean" in name_body: # 如果之前已经去过水印
                suffix = "_clean"
            
            new_filename = f"{new_base_name}{suffix}{ext}"
            new_path = os.path.join(base_dir, new_filename)
            
            if file_path != new_path:
                try:
                    os.rename(file_path, new_path)
                    print(f"Renamed: \n  {filename} \n  -> {new_filename}")
                except OSError as e:
                    print(f"Error renaming {filename}: {e}")

if __name__ == "__main__":
    rename_files()
