面向大疆一代 4G 模块的 macOS 管理软件。原生 SwiftUI，兼容 macOS 15 及以上；macOS 26+ 使用 Apple 官方 Liquid Glass 玻璃设计，旧系统自动回退为普通样式。

> 非官方第三方项目，与 DJI、Quectel 及运营商无隶属关系。

## 功能

| 功能 | 状态 | 说明 |
|---|---|---|
| 模块自动识别 | 已实现 | 自动发现 USB 2ca3:4006，热插拔轮询 |
| 模块状态 | 已实现 | 运营商、信号、网络制式、SIM 状态、USB 模式、IMEI、号码、IP |
| USB 上网模式切换 | 已实现 | 模式 0（管理）/ 1（上网）/ 2 / 3，切换后自动重启模块 |
| 网络监控 | 已实现 | 网卡、默认路由、实时速度、本次会话流量 |
| 短信收发 | 已实现 | PDU 编码（GSM 7-bit / UCS2）、收件箱、删除 |
| eSIM | 已实现 | EID、Profile 列表、启用/停用/改名/删除（SGP.22 标准指令） |
| AT 调试 | 已实现 | 任意 AT 指令、常用指令快捷按钮 |
| 短信通知 | 已实现 | 新短信系统通知 |
| 菜单栏 | 已实现 | 状态、快捷操作 |
| 菜单栏网络监控 | 已实现 | 实时上/下行速度、本次运行总流量 |
| 单元测试 | 已实现 | 短信编解码、AT 解析、eSIM 协议、网络解析（30 项） |

## 构建

要求：

- Xcode 26 或更新（含 macOS 26 SDK）
- Apple Silicon Mac（M 系列）
- 最低 macOS 15（玻璃效果需 macOS 26+）

步骤：

1. 打开 `DJ4GHub.xcodeproj`。
2. 选择 DJ4GHub scheme 与任一模拟器/本机（My Mac）。
3. Command-R 运行。

运行测试：

```
xcodebuild -project DJ4GHub.xcodeproj -scheme DJ4GHub test
```

项目内置 libusb 1.0.30（已随源码编译进应用，无需 Homebrew 或任何外部依赖）。

## 使用

1. 将 SIM 卡插入大疆一代 4G 模块并打开 DJ4GHub：
   <img width="600" alt="截屏2026-09-09 13 29 51" src="https://github.com/user-attachments/assets/a06ff1e9-1fec-4e4e-977c-27843735d644" />
2. 使用支持数据传输的 USB-C 线连接模块与 Mac。
   <img width="600" alt="截屏2026-09-09 13 29 04" src="https://github.com/user-attachments/assets/69ddf80f-f1dd-44a5-bd41-a75df7b203fa" />
3. 「上网」页选择模式 1（USB 上网）并应用，模块重启后系统网络设置会出现 Baiwang 网卡：
   <img width="600" alt="截屏2026-09-09 13 33 35" src="https://github.com/user-attachments/assets/94341995-8153-4d57-ad28-247245fa1d06" />

## 技术说明

- USB 传输：libusb 1.0.30（darwin 后端），通过 bulk 端点与模块 AT 接口通信。
- AT 指令：状态查询、`AT+QCFG="usbnet"` 模式切换、`AT+CFUN=1,1` 重启、`AT+CMGL/CMGS` 短信、`AT+CCHO/CGLA/CCHC` eUICC APDU 通道。
- 网络：读取 `ifconfig` / `route` / `netstat -ibn` 识别模块网卡、默认出口与流量。
- 界面：SwiftUI `NavigationSplitView`；玻璃样式通过兼容层自动启用——macOS 26+ 用 `glassEffect`，旧系统回退到普通磨砂材质。
- eSIM：SGP.22 ES10c 命令（STORE DATA 0x80/0xE2 + TLV），参考 lpac 实现。
- 模块为数据向设计，不支持通话语音，因此不包含来电功能。

## 路线图

- [x] eSIM Profile 管理（SGP.22）
- [x] 短信系统通知
- [x] 菜单栏快捷入口
- [x] 应用图标（用户提供的矢量图标）
- [x] 真机验证 USB/AT 通信与模式切换
- [ ] eSIM Profile 下载（SM-DP+ 激活码）
- [ ] 开发者签名（Developer ID + 公证）

## 许可

- 应用代码：MIT License，见 [LICENSE](LICENSE)。
- 内置 [libusb 1.0.30](https://libusb.info)，LGPL-2.1-or-later，许可证见 `Packages/CLibusb/COPYING`。

## 参考与致谢

本项目在开发过程中参考了以下社区项目与资料（仅参考思路与公开 AT/协议信息，未复制代码）：

- [lpac](https://github.com/estkme-group/lpac)：eUICC SGP.22 指令格式参考
- [CdricZhang/dji-cellular-as-modem](https://github.com/CdricZhang/dji-cellular-as-modem)：模块 AT 指令与 USB 模式研究
- [ppqing/dji-4g-notes](https://github.com/ppqing/dji-4g-notes)：一代模块硬件与固件折腾记录
- [wlzh/dji-4g-vohive-mac](https://github.com/wlzh/dji-4g-vohive-mac)：macOS 下模块上网方案参考

与 DJI、Quectel 及各运营商均无隶属关系；本项目为非官方第三方工具。
