# FanShift

一个快捷键在几个风扇档位之间循环切换，每个档位是一条自己画的「温度 → 转速」曲线。直接控制 Mac 的风扇，不依赖别的软件。

目前只在 M5 Pro 的 MacBook Pro（Mac17,9，macOS 27）上验证过。

## 功能

- **全局快捷键**（默认 ⌃⌥⌘8）按一次切到下一档，屏幕中央弹出档位名。
- **菜单栏**显示档位字母、温度、转速，如 `P 52° 5330`。左键切下一档，右键出菜单（直接选档位、打开设置、退出）。
- **档位类型**：
  - Auto：不接管，完全交给系统（空闲时风扇可以停转）
  - Temperature：按曲线调速，曲线在图上拖点编辑
  - Full Blast：全速，可以设 N 分钟后自动交还系统
  - Cooldown：全速，直到温度降到目标值后自动交还系统
- **Sensors 页**实时显示所有温度传感器。
- 重启后恢复上次的档位；可以设开机自启。

## 安装

需要 Xcode 命令行工具。

```bash
cd /Users/kris/Documents/FanShift && bash scripts/build-app.sh --install
```

第一次启动会弹窗要求安装后台程序，输一次密码。之后不用再输。

从旧方案（TG Pro + Hammerspoon 里的 tgpro-hotkey）切换过来，用这个脚本，它会顺便让 TG Pro 交出风扇、停用 Hammerspoon 里的旧脚本，每一步都有备份：

```bash
cd /Users/kris/Documents/FanShift && bash scripts/cutover-from-tgpro.sh
```

## 它是怎么工作的

- `FanShift.app`（普通权限）负责快捷键、界面，每 2 秒读一次温度、按当前档位算出目标转速。
- `fanshiftd`（root 后台程序）只负责把目标转速写进风扇。App 一停，它最迟 10 秒后把风扇交还系统。

细节见 [docs/design.md](docs/design.md)。

## 卸载

```bash
cd /Users/kris/Documents/FanShift && bash scripts/uninstall.sh
```

## 开发

```bash
cd /Users/kris/Documents/FanShift && swift test --build-system native   # 单元测试
cd /Users/kris/Documents/FanShift && swift build && .build/debug/fanshiftctl status   # 看风扇和温度
```

`fanshiftctl` 的其他子命令：`sensors`（列出传感器）、`shadow`（只算不写，和风扇实际目标转速并排对比）、`helper info`（后台程序的信息）。

## 许可

MIT
