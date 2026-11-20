import FanShiftCore

/// 一句界面文字的四种语言版本。四个都必须填，漏一个编译不过。
/// 没有用系统的 .lproj / 字符串目录：要在 App 里直接切换语言（不跟系统走、不用重启），
/// 而且这样每加一句话，四种语言写在同一处，不会漏。
struct Tr {
    let en: String
    let hans: String
    let hant: String
    let es: String

    var s: String {
        switch Lang.current {
        case .english: return en
        case .simplifiedChinese: return hans
        case .traditionalChinese: return hant
        case .spanish: return es
        }
    }
}

enum Lang {
    /// 当前界面语言。由 AppModel 在配置生效时设置（主线程）。
    static var current: AppLanguage = .english
}

/// 界面上所有的文字
enum L {
    // MARK: 标签页

    static let tabSettings = Tr(en: "Settings", hans: "设置", hant: "設定", es: "Ajustes")
    static let tabSensors = Tr(en: "Sensors", hans: "传感器", hant: "感測器", es: "Sensores")
    static let tabStatus = Tr(en: "Status", hans: "状态", hant: "狀態", es: "Estado")
    static let tabAbout = Tr(en: "About", hans: "关于", hant: "關於", es: "Acerca de")

    // MARK: 设置：语言、开机自启、快捷键

    static let sectionLanguage = Tr(en: "Language", hans: "语言", hant: "語言", es: "Idioma")
    static let language = Tr(en: "Language", hans: "界面语言", hant: "介面語言", es: "Idioma de la interfaz")

    static let sectionStartup = Tr(en: "Startup", hans: "开机自启", hant: "開機自動啟動", es: "Inicio")
    static func launchAtLogin(_ app: String) -> Tr {
        Tr(en: "Open \(app) at login",
           hans: "登录时自动启动 \(app)",
           hant: "登入時自動開啟 \(app)",
           es: "Abrir \(app) al iniciar sesión")
    }

    static let sectionHotkey = Tr(en: "Hotkey", hans: "快捷键", hant: "快速鍵", es: "Atajo de teclado")
    static let hotkeyEnabled = Tr(en: "Enable global hotkey", hans: "启用全局快捷键", hant: "啟用全域快速鍵", es: "Activar el atajo global")
    static let hotkeyCombo = Tr(en: "Shortcut", hans: "组合键", hant: "組合鍵", es: "Combinación")
    static let hotkeyHelp = Tr(
        en: "Click the field above, then press the shortcut (Esc to cancel). Use at least one of ⌃⌥⇧⌘.",
        hans: "点上方按钮，再按一下组合键即可绑定（Esc 取消）。修饰键 ⌃⌥⇧⌘ 至少要有一个。",
        hant: "點上方按鈕，再按一下組合鍵即可設定（Esc 取消）。修飾鍵 ⌃⌥⇧⌘ 至少要有一個。",
        es: "Haz clic en el campo de arriba y pulsa la combinación (Esc para cancelar). Usa al menos una de ⌃⌥⇧⌘.")
    static let hotkeyRecording = Tr(en: "Press the shortcut…", hans: "按下要绑定的组合键…", hant: "按下要設定的組合鍵…", es: "Pulsa la combinación…")
    static let notSet = Tr(en: "Not set", hans: "未设置", hant: "未設定", es: "Sin asignar")

    // MARK: 设置：档位

    static func sectionProfiles(_ hotkey: String) -> Tr {
        Tr(en: "Profiles (\(hotkey) cycles through them)",
           hans: "循环档位（按 \(hotkey) 在档位间循环）",
           hant: "循環檔位（按 \(hotkey) 在檔位間循環）",
           es: "Perfiles (\(hotkey) pasa de uno a otro)")
    }
    static let profilesHelp = Tr(
        en: "Click ▶ next to a profile to rename it or change its settings. Cooldown runs the fans at full speed until the chip average drops to the target, then hands them back to the system. Full Blast can hand them back after a set number of minutes.",
        hans: "点档位左侧的 ▶ 展开，可以改名、调参数。Cooldown 档：全速转，直到芯片平均温度降到目标值，再自动交还系统。Full Blast 档：可以设 N 分钟后自动交还系统。",
        hant: "點檔位左側的 ▶ 展開，可以改名、調參數。Cooldown 檔：全速轉，直到晶片平均溫度降到目標值，再自動交還系統。Full Blast 檔：可以設定 N 分鐘後自動交還系統。",
        es: "Pulsa ▶ junto a un perfil para cambiarle el nombre o los ajustes. Cooldown pone los ventiladores al máximo hasta que la media del chip baja al objetivo y luego los devuelve al sistema. Full Blast puede devolverlos al cabo de unos minutos.")
    static let noProfiles = Tr(
        en: "(Empty: add at least one profile to use the hotkey)",
        hans: "（空的：至少加一档才能使用快捷键）",
        hant: "（空的：至少加一個檔位才能使用快速鍵）",
        es: "(Vacío: añade al menos un perfil para usar el atajo)")
    static let addProfile = Tr(en: "Add profile", hans: "添加档位", hant: "新增檔位", es: "Añadir perfil")
    static let reorderHint = Tr(en: "Use ↑↓ to reorder", hans: "用 ↑↓ 调整顺序", hant: "用 ↑↓ 調整順序", es: "Usa ↑↓ para reordenar")
    static let moveUp = Tr(en: "Move up", hans: "上移", hant: "上移", es: "Subir")
    static let moveDown = Tr(en: "Move down", hans: "下移", hant: "下移", es: "Bajar")
    static let delete = Tr(en: "Delete", hans: "删除", hant: "刪除", es: "Eliminar")
    static let name = Tr(en: "Name", hans: "名字", hant: "名稱", es: "Nombre")
    static let autoHelp = Tr(
        en: "Auto leaves the fans entirely to the system (they can stop when the Mac is idle).",
        hans: "Auto 档不接管风扇，完全交给系统控制（空闲时风扇可以停转）。",
        hant: "Auto 檔不接管風扇，完全交給系統控制（閒置時風扇可以停轉）。",
        es: "Auto deja los ventiladores en manos del sistema (pueden pararse cuando el Mac está en reposo).")
    static let autoRevert = Tr(en: "Hand back to the system after a while", hans: "到点自动交还系统", hant: "時間到自動交還系統", es: "Devolver al sistema pasado un tiempo")
    static let timer = Tr(en: "Timer", hans: "倒计时", hant: "倒數計時", es: "Temporizador")
    static func minutes(_ n: Int) -> Tr { Tr(en: "\(n) min", hans: "\(n) 分钟", hant: "\(n) 分鐘", es: "\(n) min") }
    static let targetTemp = Tr(en: "Target", hans: "目标温度", hant: "目標溫度", es: "Objetivo")
    static let checkEvery = Tr(en: "Check every", hans: "检查间隔", hant: "檢查間隔", es: "Comprobar cada")
    static func seconds(_ text: String) -> Tr { Tr(en: "\(text) s", hans: "\(text) 秒", hant: "\(text) 秒", es: "\(text) s") }
    static let follows = Tr(en: "Follows", hans: "参考温度", hant: "參考溫度", es: "Sigue")

    // MARK: 设置：曲线

    static let sectionCurves = Tr(en: "Curves", hans: "曲线", hant: "曲線", es: "Curvas")
    static let curveModePicker = Tr(en: "Between two points", hans: "两个点之间怎么取值", hant: "兩個點之間怎麼取值", es: "Entre dos puntos")
    static func curveMode(_ mode: CurveMode) -> Tr {
        switch mode {
        case .step:
            return Tr(en: "Steps", hans: "阶梯", hant: "階梯", es: "Escalones")
        case .linear:
            return Tr(en: "Linear (smoother, faster fans on the same curve)",
                      hans: "连直线（更平滑，同一条曲线下转速会更高）",
                      hant: "連直線（更平滑，同一條曲線下轉速會更高）",
                      es: "Lineal (más suave; ventiladores más rápidos con la misma curva)")
        }
    }
    static let curveModeHelp = Tr(
        en: "Steps: once the temperature passes a point, that point's speed applies, and changes are spread over about 10 seconds. Linear: the speed changes in proportion between points.",
        hans: "阶梯：温度超过某个点就用那个点的转速，换转速时用大约 10 秒缓缓过渡。连直线：两个点之间按比例变化。",
        hant: "階梯：溫度超過某個點就用那個點的轉速，換轉速時用大約 10 秒緩緩過渡。連直線：兩個點之間按比例變化。",
        es: "Escalones: al superar un punto se usa su velocidad, y los cambios se reparten en unos 10 segundos. Lineal: la velocidad cambia en proporción entre los puntos.")
    static let hotCoreOffset = Tr(en: "Hottest-core offset", hans: "最热核心的温度修正", hant: "最熱核心的溫度修正", es: "Ajuste del núcleo más caliente")
    static let hotCoreOffsetHelp = Tr(
        en: "When a profile follows the hottest CPU core, this is added to the reading before looking up the curve. The default is −2 °C; 0 uses the raw reading. The menu bar always shows the raw reading.",
        hans: "参考温度选「最热的 CPU 核心」时，先在读数上加这个值再去查曲线。默认 −2°C；0 就是原始读数。菜单栏显示的始终是原始读数。",
        hant: "參考溫度選「最熱的 CPU 核心」時，先在讀數上加這個值再去查曲線。預設 −2°C；0 就是原始讀數。選單列顯示的始終是原始讀數。",
        es: "Cuando un perfil sigue el núcleo de CPU más caliente, este valor se suma a la lectura antes de consultar la curva. El valor predeterminado es −2 °C; con 0 se usa la lectura tal cual. La barra de menús siempre muestra la lectura sin ajustar.")
    static let curveTitle = Tr(en: "Curve (drag points; right-click to delete)", hans: "曲线（拖拽调点；右键删除）", hant: "曲線（拖曳調整點；按右鍵刪除）", es: "Curva (arrastra los puntos; clic derecho para eliminar)")
    static let addPoint = Tr(en: "Add a point", hans: "加一个点", hant: "加一個點", es: "Añadir un punto")
    static let loadPreset = Tr(en: "Load preset", hans: "载入预设", hant: "載入預設", es: "Cargar preajuste")
    static let deletePoint = Tr(en: "Delete this point", hans: "删除这个点", hant: "刪除這個點", es: "Eliminar este punto")
    static let curveHelp = Tr(
        en: """
            X axis 20–90 °C (5 °C per step) · Y axis 0–100 % (5 % per step) plus a Stop band at the bottom (orange).
            Percentages map onto the fan's speed range (0 % = minimum, 100 % = maximum).
            Drag a point into the Stop band to leave that range to the system (the fans can stop). The hollow circle is the current temperature on this curve.
            """,
        hans: """
            X 轴 20–90°C（5°C 一格） · Y 轴 0–100%（5% 一格）+ 底部 Stop 档（橙色）。
            百分比按风扇转速范围折算（0% = 最低转速，100% = 最高转速）。
            把点拖到 Stop 区表示这一段不接管，交还系统（风扇可以停转）。空心圆圈是当前温度在这条曲线上的位置。
            """,
        hant: """
            X 軸 20–90°C（5°C 一格） · Y 軸 0–100%（5% 一格）+ 底部 Stop 檔（橙色）。
            百分比依風扇轉速範圍換算（0% = 最低轉速，100% = 最高轉速）。
            把點拖到 Stop 區表示這一段不接管，交還系統（風扇可以停轉）。空心圓圈是目前溫度在這條曲線上的位置。
            """,
        es: """
            Eje X 20–90 °C (pasos de 5 °C) · eje Y 0–100 % (pasos de 5 %) y una franja Stop abajo (naranja).
            Los porcentajes se aplican al rango del ventilador (0 % = mínimo, 100 % = máximo).
            Arrastra un punto a la franja Stop para dejar ese tramo al sistema (los ventiladores pueden pararse). El círculo hueco es la temperatura actual en esta curva.
            """)

    // MARK: 设置：菜单栏

    static let sectionMenuBar = Tr(en: "Menu bar", hans: "菜单栏", hant: "選單列", es: "Barra de menús")
    static let menuBarStyle = Tr(en: "Style", hans: "样式", hant: "樣式", es: "Estilo")
    static func menuBarStyle(_ style: MenuBarStyle) -> Tr {
        switch style {
        case .inline:
            return Tr(en: "One line (P 52° 5330)", hans: "一行（P 52° 5330）", hant: "一行（P 52° 5330）", es: "Una línea (P 52° 5330)")
        case .stackedRPMAbove:
            return Tr(en: "Two lines, RPM on top", hans: "两行，转速在上", hant: "兩行，轉速在上", es: "Dos líneas, RPM arriba")
        case .stackedRPMBelow:
            return Tr(en: "Two lines, RPM below", hans: "两行，转速在下", hant: "兩行，轉速在下", es: "Dos líneas, RPM abajo")
        }
    }
    static let separateLetter = Tr(en: "Show the profile letter as its own item", hans: "档位字母单独放一个图标", hant: "檔位字母單獨放一個圖示", es: "Mostrar la letra del perfil como un elemento aparte")
    static let showTemp = Tr(en: "Show temperature", hans: "显示温度", hant: "顯示溫度", es: "Mostrar temperatura")
    static let showRPM = Tr(en: "Show fan speed", hans: "显示转速", hant: "顯示轉速", es: "Mostrar velocidad del ventilador")
    static let secondTemp = Tr(en: "Second temperature", hans: "第二个温度", hant: "第二個溫度", es: "Segunda temperatura")
    static let none = Tr(en: "None", hans: "不显示", hant: "不顯示", es: "Ninguna")
    static func colorTemps(warm: Int, hot: Int) -> Tr {
        Tr(en: "Color hot temperatures (orange from \(warm) °C, red from \(hot) °C)",
           hans: "温度高时变色（\(warm)°C 起橙色，\(hot)°C 起红色）",
           hant: "溫度高時變色（\(warm)°C 起橙色，\(hot)°C 起紅色）",
           es: "Colorear temperaturas altas (naranja desde \(warm) °C, rojo desde \(hot) °C)")
    }
    static let menuBarHelp = Tr(
        en: "The two-line style stacks small text and takes less space. The first temperature is the one the current profile follows. With a separate letter, click the letter to switch profiles and click the readout for the menu. Hold ⌘ and drag to move either item. If the menu bar is crowded or an item hides behind the notch, turn off the temperature or the fan speed.",
        hans: "两行样式是小字叠两行，比一行窄。第一个温度是当前档位参考的那个温度。字母单独一个图标时：点字母切下一档，点读数出菜单；两个图标都可以按住 ⌘ 拖动换位置。菜单栏放不下、图标被刘海挡住时，可以关掉温度或转速。",
        hant: "兩行樣式是小字疊兩行，比一行窄。第一個溫度是目前檔位參考的那個溫度。字母單獨一個圖示時：點字母切到下一檔，點讀數打開選單；兩個圖示都可以按住 ⌘ 拖曳換位置。選單列放不下、圖示被瀏海擋住時，可以關掉溫度或轉速。",
        es: "El estilo de dos líneas apila texto pequeño y ocupa menos. La primera temperatura es la que sigue el perfil actual. Con la letra aparte, haz clic en la letra para cambiar de perfil y en la lectura para abrir el menú. Mantén ⌘ y arrastra para mover cualquiera de los dos. Si la barra de menús está llena o un elemento queda detrás de la muesca, desactiva la temperatura o la velocidad.")

    // MARK: 设置：提示、保存

    static let sectionAlert = Tr(en: "On-screen alert", hans: "屏幕提示", hant: "螢幕提示", es: "Aviso en pantalla")
    static let alertEnabled = Tr(en: "Show an alert in the middle of the screen", hans: "启用屏幕中央提示", hant: "啟用螢幕中央提示", es: "Mostrar un aviso en el centro de la pantalla")
    static let cooldownText = Tr(en: "Cooldown finished text", hans: "Cooldown 结束文字", hant: "Cooldown 結束文字", es: "Texto al terminar Cooldown")
    static let alertDuration = Tr(en: "Duration", hans: "显示时长", hant: "顯示時間", es: "Duración")
    static let unsavedChanges = Tr(en: "Unsaved changes", hans: "有未保存的修改", hant: "有未儲存的修改", es: "Cambios sin guardar")
    static let discard = Tr(en: "Discard", hans: "放弃修改", hant: "放棄修改", es: "Descartar")
    static let saveAndApply = Tr(en: "Save and Apply", hans: "保存并生效", hant: "儲存並套用", es: "Guardar y aplicar")
    static let saved = Tr(en: "Saved and applied", hans: "已保存并生效", hant: "已儲存並套用", es: "Guardado y aplicado")

    // MARK: 参考温度 / 传感器

    static let sensorHottestCore = Tr(en: "Hottest CPU core", hans: "最热的 CPU 核心", hant: "最熱的 CPU 核心", es: "Núcleo de CPU más caliente")
    static let sensorHottestCoreRecommended = Tr(
        en: "Hottest CPU core (recommended)",
        hans: "最热的 CPU 核心（推荐）",
        hant: "最熱的 CPU 核心（建議）",
        es: "Núcleo de CPU más caliente (recomendado)")
    static let sensorChipAverage = Tr(en: "Chip average", hans: "芯片各温度点的平均", hant: "晶片各溫度點的平均", es: "Media del chip")
    static let sensorHottestAny = Tr(en: "Hottest sensor (including SSD and battery)", hans: "所有传感器里最热的（含硬盘、电池）", hant: "所有感測器裡最熱的（含硬碟、電池）", es: "Sensor más caliente (incluye SSD y batería)")
    static func unavailable(_ name: String) -> Tr {
        Tr(en: "\(name) (not available right now)", hans: "\(name)（现在读不到）", hant: "\(name)（目前讀不到）", es: "\(name) (no disponible ahora)")
    }
    /// 传感器在界面上显示的名字：核心温度按语言翻译，其余是系统给的原名
    static func sensorName(_ name: String) -> String {
        guard let key = SensorMath.coreKey(name) else { return name }
        return Tr(en: "CPU core \(key)", hans: "CPU 核心 \(key)", hant: "CPU 核心 \(key)", es: "Núcleo CPU \(key)").s
    }

    static let sensorsTitle = Tr(en: "Temperature sensors", hans: "温度传感器实时监控", hant: "溫度感測器即時監控", es: "Sensores de temperatura")
    static let filterPlaceholder = Tr(en: "Filter by name (e.g. core, tdie, NAND)", hans: "过滤名字（如 核心、tdie、NAND）", hant: "篩選名稱（如 核心、tdie、NAND）", es: "Filtrar por nombre (p. ej. núcleo, tdie, NAND)")
    static let sortByTemp = Tr(en: "Sort by temperature", hans: "按温度排序", hant: "依溫度排序", es: "Ordenar por temperatura")
    static func sensorCount(_ n: Int) -> Tr {
        Tr(en: "\(n) sensors, refreshed every 2 s", hans: "共 \(n) 个，每 2 秒刷新", hant: "共 \(n) 個，每 2 秒更新", es: "\(n) sensores, se actualizan cada 2 s")
    }
    static let kindCore = Tr(en: "core", hans: "核心", hant: "核心", es: "núcleo")
    static let kindDie = Tr(en: "die", hans: "芯片", hant: "晶片", es: "chip")
    static let kindCalibration = Tr(en: "calib.", hans: "校准值", hant: "校準值", es: "calib.")
    static let sensorsHelp = Tr(
        en: "“core” readings are the CPU cores; curves follow the hottest one by default. “die” readings are points on the chip; Cooldown follows their average. Choose what each profile follows in Settings: expand a profile and pick Follows.",
        hans: "「核心」是各 CPU 核心的温度，曲线默认参考其中最热的一个；「芯片」是芯片上的温度点，Cooldown 参考它们的平均。每个档位参考哪个温度，在设置里展开档位，在「参考温度」里选。",
        hant: "「核心」是各 CPU 核心的溫度，曲線預設參考其中最熱的一個；「晶片」是晶片上的溫度點，Cooldown 參考它們的平均。每個檔位參考哪個溫度，在設定裡展開檔位，在「參考溫度」裡選。",
        es: "«núcleo» son los núcleos de la CPU; por defecto las curvas siguen el más caliente. «chip» son puntos de medida del chip; Cooldown sigue su media. Elige qué sigue cada perfil en Ajustes: despliega un perfil y usa «Sigue».")

    // MARK: 状态页

    static let statusTitle = Tr(en: "Status", hans: "当前状态", hant: "目前狀態", es: "Estado actual")
    static let helperRow = Tr(en: "Helper (writes the fan speeds)", hans: "后台程序（负责把转速写进风扇）", hant: "背景程式（負責把轉速寫進風扇）", es: "Servicio auxiliar (escribe la velocidad de los ventiladores)")
    static let dryRun = Tr(en: "Dry run: commands are only printed, the fans are not touched", hans: "演练模式：只打印指令，不碰风扇", hant: "演練模式：只印出指令，不碰風扇", es: "Simulación: los comandos solo se imprimen y no se tocan los ventiladores")
    static let installHelper = Tr(en: "Install Helper…", hans: "安装后台程序…", hant: "安裝背景程式…", es: "Instalar servicio auxiliar…")
    static let reinstallHelper = Tr(en: "Reinstall Helper…", hans: "重新安装后台程序…", hant: "重新安裝背景程式…", es: "Reinstalar servicio auxiliar…")
    static let uninstallHelper = Tr(en: "Uninstall Helper…", hans: "卸载后台程序…", hant: "解除安裝背景程式…", es: "Desinstalar servicio auxiliar…")
    static func installFailedMessage(_ e: String) -> Tr { Tr(en: "Install failed: \(e)", hans: "安装没成功：\(e)", hant: "安裝失敗：\(e)", es: "No se pudo instalar: \(e)") }
    static let installed = Tr(en: "Installed", hans: "已安装", hant: "已安裝", es: "Instalado")
    static func uninstallFailedMessage(_ e: String) -> Tr { Tr(en: "Uninstall failed: \(e)", hans: "卸载没成功：\(e)", hant: "解除安裝失敗：\(e)", es: "No se pudo desinstalar: \(e)") }
    static let uninstalled = Tr(en: "Uninstalled; the fans are fully under system control", hans: "已卸载，风扇完全交给系统", hant: "已解除安裝，風扇完全交給系統", es: "Desinstalado; los ventiladores quedan en manos del sistema")
    static func currentProfile(_ name: String) -> Tr { Tr(en: "Current profile: \(name)", hans: "当前档位：\(name)", hant: "目前檔位：\(name)", es: "Perfil actual: \(name)") }
    static func fanRow(_ index: Int, _ rpm: Int) -> Tr { Tr(en: "Fan \(index): \(rpm) RPM", hans: "风扇 \(index)：\(rpm) RPM", hant: "風扇 \(index)：\(rpm) RPM", es: "Ventilador \(index): \(rpm) RPM") }
    static func fanDetail(target: Int, min: Int, max: Int, mode: String) -> Tr {
        Tr(en: "Target \(target) · range \(min)–\(max) · \(mode)",
           hans: "目标 \(target) · 范围 \(min)–\(max) · \(mode)",
           hant: "目標 \(target) · 範圍 \(min)–\(max) · \(mode)",
           es: "Objetivo \(target) · rango \(min)–\(max) · \(mode)")
    }
    static let fans = Tr(en: "Fans", hans: "风扇", hant: "風扇", es: "Ventiladores")
    static let noFanInfo = Tr(en: "Cannot read the fans", hans: "读不到风扇信息", hant: "讀不到風扇資訊", es: "No se pueden leer los ventiladores")
    static func hiddenTitle(_ app: String) -> Tr {
        Tr(en: "The menu bar is full, so \(app)'s item is hidden",
           hans: "菜单栏放不下，\(app) 的图标现在看不见",
           hant: "選單列放不下，\(app) 的圖示現在看不到",
           es: "La barra de menús está llena y el elemento de \(app) está oculto")
    }
    static let hiddenDetail = Tr(
        en: "There are too many menu bar items on the right, so macOS hides the ones that don't fit (behind the notch on screens that have one). In Settings → Menu bar you can switch to the two-line style or turn off the temperature or fan speed; removing other menu bar items also helps. The hotkey still works.",
        hans: "右边的菜单栏图标太多，系统把排不下的藏起来了（有刘海的屏幕上是藏到刘海底下）。可以在设置的「菜单栏」里换成两行样式、关掉温度或转速，或者减少其他菜单栏图标。快捷键不受影响。",
        hant: "右邊的選單列圖示太多，系統把排不下的藏起來了（有瀏海的螢幕上是藏到瀏海底下）。可以在設定的「選單列」裡換成兩行樣式、關掉溫度或轉速，或者減少其他選單列圖示。快速鍵不受影響。",
        es: "Hay demasiados elementos a la derecha de la barra de menús y macOS oculta los que no caben (detrás de la muesca en las pantallas que la tienen). En Ajustes → Barra de menús puedes usar el estilo de dos líneas o desactivar la temperatura o la velocidad; quitar otros elementos también ayuda. El atajo sigue funcionando.")
    static let otherControllerTitle = Tr(en: "Another app is controlling the fans", hans: "另一个软件正在控制风扇", hant: "另一個軟體正在控制風扇", es: "Otra app está controlando los ventiladores")
    static func otherControllerDetail(_ app: String) -> Tr {
        Tr(en: "The fans are in manual mode, but not because of \(app). Two apps controlling the fans overwrite each other; quit the other one while using \(app).",
           hans: "风扇处在手动模式，但不是 \(app) 设的。两个软件同时控制风扇会互相覆盖，用 \(app) 时请退出另一个。",
           hant: "風扇處於手動模式，但不是 \(app) 設定的。兩個軟體同時控制風扇會互相覆蓋，使用 \(app) 時請結束另一個。",
           es: "Los ventiladores están en modo manual, pero no por \(app). Dos apps que controlan los ventiladores se pisan entre sí; cierra la otra mientras uses \(app).")
    }
    static let lastError = Tr(en: "Last error", hans: "最近一次出错", hant: "最近一次錯誤", es: "Último error")
    static func configFile(_ path: String) -> Tr { Tr(en: "Configuration: \(path)", hans: "配置文件：\(path)", hant: "設定檔：\(path)", es: "Configuración: \(path)") }
    static func menuBarItems(_ d: String) -> Tr { Tr(en: "Menu bar items: \(d)", hans: "菜单栏项：\(d)", hant: "選單列項目：\(d)", es: "Elementos de la barra de menús: \(d)") }
    static let migrated = Tr(
        en: "This configuration was copied from the old version (~/.hammerspoon/tgpro-hotkey-config.json) on first launch. The old file was left as it was.",
        hans: "这份配置是第一次启动时从旧版（~/.hammerspoon/tgpro-hotkey-config.json）搬过来的，旧文件没有动。",
        hant: "這份設定是第一次啟動時從舊版（~/.hammerspoon/tgpro-hotkey-config.json）搬過來的，舊檔案沒有動。",
        es: "Esta configuración se copió de la versión anterior (~/.hammerspoon/tgpro-hotkey-config.json) en el primer arranque. El archivo antiguo no se tocó.")
    static func following(_ temp: String) -> Tr { Tr(en: "Following \(temp) °C", hans: "参考温度 \(temp)°C", hant: "參考溫度 \(temp)°C", es: "Siguiendo \(temp) °C") }
    static let noTemp = Tr(en: "No temperature reading", hans: "读不到温度", hant: "讀不到溫度", es: "Sin lectura de temperatura")
    static func targetPercent(_ p: Int) -> Tr { Tr(en: "target \(p)%", hans: "目标 \(p)%", hant: "目標 \(p)%", es: "objetivo \(p) %") }
    static let notApplied = Tr(en: " (not applied: the helper is unavailable)", hans: "（没有生效：后台程序不可用）", hant: "（沒有生效：背景程式無法使用）", es: " (sin efecto: el servicio auxiliar no está disponible)")
    static let fansReleased = Tr(en: "fans handed back to the system", hans: "风扇已交还系统", hant: "風扇已交還系統", es: "ventiladores devueltos al sistema")
    static let modeForced = Tr(en: "controlled by \(FanShiftInfo.appName)", hans: "由 \(FanShiftInfo.appName) 接管", hant: "由 \(FanShiftInfo.appName) 接管", es: "controlado por \(FanShiftInfo.appName)")
    static let modeSystem = Tr(en: "system control", hans: "系统控制", hant: "系統控制", es: "control del sistema")
    static func modeOther(_ m: Int) -> Tr { Tr(en: "mode \(m)", hans: "模式 \(m)", hant: "模式 \(m)", es: "modo \(m)") }

    // MARK: 关于

    static func version(_ v: String) -> Tr { Tr(en: "Version \(v)", hans: "版本 \(v)", hant: "版本 \(v)", es: "Versión \(v)") }
    static let devBuild = Tr(en: "development build", hans: "开发版", hant: "開發版", es: "versión de desarrollo")
    static let tagline = Tr(
        en: "Cycle through your own fan curves with one hotkey",
        hans: "一个快捷键循环切换风扇档位，每个档位一条自己画的温度曲线",
        hant: "一個快速鍵循環切換風扇檔位，每個檔位一條自己畫的溫度曲線",
        es: "Pasa de una curva de ventilador propia a otra con un solo atajo")

    // MARK: 后台程序

    static let helperChecking = Tr(en: "Checking…", hans: "检查中…", hant: "檢查中…", es: "Comprobando…")
    static let helperNotInstalled = Tr(en: "Not installed", hans: "还没安装", hant: "尚未安裝", es: "No instalado")
    static let helperRunning = Tr(en: "Running", hans: "运行正常", hant: "運作正常", es: "Funcionando")
    static func helperOutdated(installed: String, needed: String) -> Tr {
        Tr(en: "Wrong version (installed \(installed), needs \(needed)); please reinstall",
           hans: "版本不对（装的是 \(installed)，需要 \(needed)），请重装",
           hant: "版本不對（裝的是 \(installed)，需要 \(needed)），請重新安裝",
           es: "Versión incorrecta (instalada \(installed), se necesita \(needed)); reinstálalo")
    }
    static func cannotReachHelper(_ e: String) -> Tr {
        Tr(en: "Cannot reach the helper: \(e)", hans: "连不上后台程序：\(e)", hant: "連不上背景程式：\(e)", es: "No se puede contactar con el servicio auxiliar: \(e)")
    }
    static let cannotReachHelperShort = Tr(en: "Cannot reach the helper", hans: "连不上后台程序", hant: "連不上背景程式", es: "No se puede contactar con el servicio auxiliar")
    static let badInterface = Tr(en: "Unexpected helper interface", hans: "后台程序的接口不对", hant: "背景程式的介面不符", es: "Interfaz del servicio auxiliar inesperada")
    static let badReply = Tr(en: "Could not understand the helper's reply", hans: "后台程序的应答看不懂", hant: "看不懂背景程式的回應", es: "No se entiende la respuesta del servicio auxiliar")
    static let noReply = Tr(en: "The helper did not respond", hans: "后台程序没有应答", hant: "背景程式沒有回應", es: "El servicio auxiliar no responde")
    static let runFailed = Tr(en: "Failed", hans: "执行失败", hant: "執行失敗", es: "Error")
    static let noBundledHelper = Tr(
        en: "This copy of the app doesn't include the helper. Build it with scripts/build-app.sh and install from that copy.",
        hans: "App 里没有带后台程序，请用 scripts/build-app.sh 打包后的 App 来安装。",
        hant: "App 裡沒有附背景程式，請用 scripts/build-app.sh 打包後的 App 來安裝。",
        es: "Esta copia de la app no incluye el servicio auxiliar. Compílala con scripts/build-app.sh e instálalo desde esa copia.")
    static func installPrompt(_ app: String) -> Tr {
        Tr(en: "\(app) wants to install the helper that controls the fans.",
           hans: "\(app) 要安装控制风扇用的后台程序。",
           hant: "\(app) 要安裝控制風扇用的背景程式。",
           es: "\(app) quiere instalar el servicio auxiliar que controla los ventiladores.")
    }
    static func uninstallPrompt(_ app: String) -> Tr {
        Tr(en: "\(app) wants to uninstall the helper that controls the fans.",
           hans: "\(app) 要卸载控制风扇用的后台程序。",
           hant: "\(app) 要解除安裝控制風扇用的背景程式。",
           es: "\(app) quiere desinstalar el servicio auxiliar que controla los ventiladores.")
    }
    static let installAlertTitle = Tr(en: "Install the Fan Helper", hans: "安装控制风扇用的后台程序", hant: "安裝控制風扇用的背景程式", es: "Instalar el servicio auxiliar de ventiladores")
    static func installAlertBody(_ app: String) -> Tr {
        Tr(en: "\(app) uses a small program that runs as root to set the fan speed. Installing it asks for your password once. Without it, \(app) can only show temperatures and fan speeds.",
           hans: "\(app) 要靠一个以 root 身份运行的小程序来调风扇转速，装的时候需要输一次密码。不装的话只能显示温度和转速，不能控制风扇。",
           hant: "\(app) 要靠一個以 root 身分執行的小程式來調整風扇轉速，安裝時需要輸入一次密碼。不安裝的話只能顯示溫度和轉速，不能控制風扇。",
           es: "\(app) usa un pequeño programa que se ejecuta como root para ajustar la velocidad de los ventiladores. Al instalarlo te pedirá la contraseña una vez. Sin él, \(app) solo puede mostrar temperaturas y velocidades.")
    }
    static let installNow = Tr(en: "Install", hans: "现在安装", hant: "現在安裝", es: "Instalar")
    static let later = Tr(en: "Later", hans: "以后再说", hant: "以後再說", es: "Más tarde")
    static let installFailedTitle = Tr(en: "Installation Failed", hans: "安装失败", hant: "安裝失敗", es: "Error en la instalación")

    // MARK: 菜单、提示

    static let hotkeyFailed = Tr(en: "Could not register the hotkey", hans: "快捷键注册失败", hant: "快速鍵註冊失敗", es: "No se pudo registrar el atajo")
    static let noProfilesAlert = Tr(en: "No profiles", hans: "循环列表为空", hant: "循環清單是空的", es: "No hay perfiles")
    static func quit(_ app: String) -> Tr { Tr(en: "Quit \(app)", hans: "退出 \(app)", hant: "結束 \(app)", es: "Salir de \(app)") }
    static let settingsMenu = Tr(en: "Settings…", hans: "设置…", hant: "設定…", es: "Ajustes…")
    static func helperInMenu(_ summary: String) -> Tr { Tr(en: "Helper: \(summary)", hans: "后台程序：\(summary)", hant: "背景程式：\(summary)", es: "Servicio auxiliar: \(summary)") }
    static func tipCycle(_ step: String, hotkey: String?) -> Tr {
        let en = hotkey.map { " (or \($0))" } ?? ""
        let zh = hotkey.map { "（同 \($0)）" } ?? ""
        let es = hotkey.map { " (o \($0))" } ?? ""
        return Tr(en: "\(step). Click for the next profile\(en), right-click for the menu",
                  hans: "\(step)。点击切下一档\(zh)，右键打开菜单",
                  hant: "\(step)。點一下切到下一檔\(zh)，按右鍵打開選單",
                  es: "\(step). Clic para el siguiente perfil\(es), clic derecho para el menú")
    }
    static func tipMenu(_ step: String) -> Tr { Tr(en: "\(step). Click for the menu", hans: "\(step)。点击打开菜单", hant: "\(step)。點一下打開選單", es: "\(step). Clic para abrir el menú") }

    static let menuEdit = Tr(en: "Edit", hans: "编辑", hant: "編輯", es: "Edición")
    static let undo = Tr(en: "Undo", hans: "撤销", hant: "還原", es: "Deshacer")
    static let cut = Tr(en: "Cut", hans: "剪切", hant: "剪下", es: "Cortar")
    static let copy = Tr(en: "Copy", hans: "拷贝", hant: "拷貝", es: "Copiar")
    static let paste = Tr(en: "Paste", hans: "粘贴", hant: "貼上", es: "Pegar")
    static let selectAll = Tr(en: "Select All", hans: "全选", hant: "全選", es: "Seleccionar todo")
    static let menuWindow = Tr(en: "Window", hans: "窗口", hant: "視窗", es: "Ventana")
    static let close = Tr(en: "Close", hans: "关闭", hant: "關閉", es: "Cerrar")
}
