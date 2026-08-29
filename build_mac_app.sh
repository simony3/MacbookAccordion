#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

python3 -m venv .venv
source .venv/bin/activate

python -m pip install -U pip wheel
python -m pip install py2app pygame-ce numpy pybooklid sounddevice

# py2app / pygame-ce 会把这些默认图标带进应用包。全部强制替换成应用图标，
# 避免窗口创建期间短暂显示 Pygame 自带的黄色卡通图标。
PKG_DIR=$(PYGAME_HIDE_SUPPORT_PROMPT=1 python -c "import pygame, os; print(os.path.dirname(pygame.__file__))" | tail -1)
cp assets/MacbookAccordion.icns "$PKG_DIR/pygame_icon.icns"
sips -z 256 256 -s format bmp assets/MacbookAccordion-AppIcon.png \
    --out "$PKG_DIR/pygame_icon_mac.bmp" >/dev/null
cp "$PKG_DIR/pygame_icon_mac.bmp" "$PKG_DIR/pygame_icon.bmp"

rm -rf build dist
python setup.py py2app

# 直接装进「应用程序」，并清掉 dist：留着的话 dist 里那个 .app 会被 Launch Services
# 一起索引，Launchpad / 聚焦里就会出现两个一模一样的 MacbookAccordion
APP="/Applications/MacbookAccordion.app"
if pgrep -f "MacbookAccordion.app/Contents/MacOS" >/dev/null; then
    echo "提示：MacbookAccordion 正在运行，装完请退出重开才会用到新版本"
fi
rm -rf "$APP"
ditto dist/MacbookAccordion.app "$APP"
# 打包期间 dist 里的 .app 已经被 Launch Services 记了一笔，删文件不会自动销记录
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$PWD/dist/MacbookAccordion.app" 2>/dev/null || true
rm -rf build dist

echo "Done: $APP"
echo "Run:"
echo "  open -a MacbookAccordion"
