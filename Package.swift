// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FanShift",
    platforms: [.macOS(.v14)],
    targets: [
        // AppleSMC 的 C 封装（结构体布局必须和内核一致，所以用 C 写）
        .target(
            name: "CSMC",
            path: "Sources/CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // 纯逻辑 + 硬件读写：曲线、档位状态机、配置、传感器、风扇
        .target(name: "FanShiftCore", dependencies: ["CSMC"]),
        // root 后台程序：唯一往风扇寄存器里写东西的地方
        .executableTarget(name: "fanshiftd", dependencies: ["FanShiftCore"]),
        // 命令行诊断工具
        .executableTarget(name: "fanshiftctl", dependencies: ["FanShiftCore"]),
        // 菜单栏 App（打包时改名为 FanShift）
        .executableTarget(name: "FanShiftApp", dependencies: ["FanShiftCore"]),
        .testTarget(name: "FanShiftCoreTests", dependencies: ["FanShiftCore"]),
    ]
)
