在进行ios开发时，不用xcode编译，我自己编译后若报错，会贴报错信息的。
进行鸿蒙/安卓开发时，用命令行编译。

编码规则：
- 始终按 UTF-8 读写和解析文件、命令输出、日志、JSON 与路径，尤其是包含中文的路径。
- 如果遇到类似 \xe6\xb8\xb8\xe6\x88\x8f 的字节转义，优先把它当作 UTF-8 字节序列还原为中文，不要按 Latin-1/ASCII 解释。
- 生成 JSON、HTTP header、环境变量或跨进程序列化内容时，中文路径需要使用 UTF-8，并在 HTTP header 中使用 ASCII-safe 表示（例如 JSON 转义、percent-encoding 或 base64），避免把原始非 ASCII 字节直接塞进 header。
