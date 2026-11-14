#!/bin/bash
# 重新生成全部交付物：三张 1024 PNG、三个 iconset、三个 .icns、preview.png、qa/ 自查图。
# 用法： bash icon/build.sh（在仓库根目录下）。当前用的是方案 C，生成后把 icon/icon-C.icns 拷到 Resources/AppIcon.icns。
# 只用系统自带工具（swiftc / sips / iconutil），不联网，不打开任何窗口。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

mkdir -p .build
swiftc -O make_icons.swift -o .build/make_icons

.build/make_icons render "$DIR"

for v in A B C; do
  set_dir="icon-$v.iconset"
  rm -rf "$set_dir"; mkdir "$set_dir"
  while read -r px name; do
    if [ "$px" = 1024 ]; then
      cp "icon-$v-1024.png" "$set_dir/$name.png"
    else
      sips -z "$px" "$px" "icon-$v-1024.png" --out "$set_dir/$name.png" >/dev/null
    fi
  done <<'EOF'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
EOF
  rm -f "icon-$v.icns"
  iconutil -c icns "$set_dir" -o "icon-$v.icns"
done

.build/make_icons preview "$DIR"
echo "done: $DIR"
