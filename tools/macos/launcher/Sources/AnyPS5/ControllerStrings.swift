import AnyPS5Core
import Foundation

/// Settings → Controllers, the controller test and the troubleshooter: their texts, in both languages.
enum TP {
    enum Key: String, CaseIterable {
        case title = "padTitle", noneConnected = "padNone", noneConnectedDetail = "padNoneDetail", playerOne = "padPlayerOne", testInputs = "padTest", testInputsDetail = "padTestDetail", testVibration = "padVibrate", testVibrationDetail = "padVibrateDetail"
        case light = "padLight", lightDetail = "padLightDetail", lightTheme = "padLight_theme", lightBlue = "padLight_blue", lightRed = "padLight_red", lightGreen = "padLight_green", lightPurple = "padLight_purple", lightPink = "padLight_pink", lightOrange = "padLight_orange", lightWhite = "padLight_white", lightOff = "padLight_off"
        case confirm = "padConfirm", confirmDetail = "padConfirmDetail", confirmCross = "padConfirmCross", confirmCircle = "padConfirmCircle", deadzone = "padDeadzone", deadzoneDetail = "padDeadzoneDetail"
        case usb = "padUsb", bluetooth = "padBluetooth", connectionUnknown = "padConnected", battery = "padBattery", batteryAbout = "padBatteryAbout", charging = "padCharging", generic = "padGeneric"
        case troubleshoot = "padTroubleshoot", allGood = "padAllGood", allGoodDetail = "padAllGoodLauncherDetail"
        case noControllers = "padFinding_noControllers", noControllersDetail = "padFinding_noControllersDetail", usbCable = "padFinding_usbCable", usbCableDetail = "padFinding_usbCableDetail", bluetoothPairing = "padFinding_bluetoothPairing", bluetoothPairingDetail = "padFinding_bluetoothPairingDetail"
        case dualShock3 = "padDualShock3", dualShock3Detail = "padDualShock3Detail", unmapped = "padFinding_unmapped", unmappedDetail = "padFinding_unmappedDetail", lowBattery = "padFinding_lowBattery", lowBatteryDetail = "padFinding_lowBatteryDetail", steamRunning = "padFinding_steamRunning", steamRunningDetail = "padFinding_steamRunningDetail"
        case testTitle = "padTestTitle", testHoldToLeave = "padHoldToLeave", testLeave = "padLeave", testNoPad = "padTestNoPad", testSticks = "padSticks", testTriggers = "padTriggers", vibrated = "padVibrating", noVibration = "padNoVibration"
        case connected = "padArrived", disconnected = "padLeft"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    static func light(_ light: PadLight) -> String {
        switch light {
        case .theme: return text(.lightTheme)
        case .blue: return text(.lightBlue)
        case .red: return text(.lightRed)
        case .green: return text(.lightGreen)
        case .purple: return text(.lightPurple)
        case .pink: return text(.lightPink)
        case .orange: return text(.lightOrange)
        case .white: return text(.lightWhite)
        case .off: return text(.lightOff)
        }
    }

    static func kind(_ kind: PadKind) -> String { kind == .generic ? text(.generic) : kind.reportName }

    static func connection(_ connection: PadConnection) -> String {
        switch connection {
        case .usb: return text(.usb)
        case .bluetooth: return text(.bluetooth)
        case .unknown: return text(.connectionUnknown)
        }
    }

    /// "DualSense · Bluetooth · 80% · charging".
    static func summary(_ pad: PadInfo) -> String {
        var parts = [kind(pad.kind), connection(pad.connection)]
        if let battery = pad.battery {
            parts.append(format(battery.approximate ? .batteryAbout : .battery, battery.percent))
            if battery.charging == true { parts.append(text(.charging)) }
        }
        return parts.joined(separator: " · ")
    }

    /// A finding's title and what to do.
    static func finding(_ finding: PadTroubleshooter.Finding) -> (title: String, detail: String) {
        switch finding {
        case .noControllers: return (text(.noControllers), text(.noControllersDetail))
        case .usbCable: return (text(.usbCable), text(.usbCableDetail))
        case .bluetoothPairing: return (text(.bluetoothPairing), text(.bluetoothPairingDetail))
        case .dualShock3: return (text(.dualShock3), text(.dualShock3Detail))
        case .unmapped(let name): return (format(.unmapped, name), text(.unmappedDetail))
        case .lowBattery(let name, let percent): return (format(.lowBattery, name, percent), text(.lowBatteryDetail))
        case .steamRunning: return (text(.steamRunning), text(.steamRunningDetail))
        }
    }

    static let english: [Key: String] = [
        .title: "Controllers",
        .noneConnected: "No controller connected",
        .noneConnectedDetail: "Plug one in with a USB cable or pair it over Bluetooth; the troubleshooter below says what to check",
        .playerOne: "Player 1",
        .testInputs: "Test Buttons and Sticks",
        .testInputsDetail: "Every button, both sticks and the triggers, live",
        .testVibration: "Test Vibration",
        .testVibrationDetail: "A few strong pulses on Player 1's controller",
        .light: "Light Bar",
        .lightDetail: "DualSense and DualShock 4, while the launcher is in front; games set their own",
        .lightTheme: "Theme Colour", .lightBlue: "Blue", .lightRed: "Red", .lightGreen: "Green", .lightPurple: "Purple",
        .lightPink: "Pink", .lightOrange: "Orange", .lightWhite: "White", .lightOff: "Off",
        .confirm: "Confirm Button",
        .confirmDetail: "Circle confirms and Cross goes back, as on Japanese consoles; the hints follow",
        .confirmCross: "✕ Cross", .confirmCircle: "○ Circle",
        .deadzone: "Stick Dead Zone",
        .deadzoneDetail: "A resting stick's drift is ignored, in the launcher and in games that set no dead zone of their own",
        .usb: "USB", .bluetooth: "Bluetooth", .connectionUnknown: "Connected",
        .battery: "%d%%", .batteryAbout: "about %d%%", .charging: "charging", .generic: "Controller",
        .troubleshoot: "Troubleshooting",
        .allGood: "Nothing in the way",
        .allGoodDetail: "The launcher reads every controller connected; games read them through SDL",
        .noControllers: "macOS sees no controller",
        .noControllersDetail: "Neither over USB nor over Bluetooth. Check the tips below, then press the PS, Xbox or Home button",
        .usbCable: "USB: a cable that carries data",
        .usbCableDetail: "Many cables only charge. Use the controller's own cable or one you know moves files, straight into the Mac",
        .bluetoothPairing: "Bluetooth: pair it in System Settings",
        .bluetoothPairingDetail: "DualSense and DualShock 4: hold PS and Create (Share) until the light flashes. Xbox: hold the pair button. Switch Pro: hold the sync button. Then System Settings → Bluetooth → Connect",
        .dualShock3: "DualShock 3: over USB only",
        .dualShock3Detail: "macOS cannot pair a DualShock 3 over Bluetooth. Plug it in with a USB cable and press PS: the launcher reads it itself",
        .unmapped: "%@ has no layout on macOS",
        .unmappedDetail: "macOS lists it but the launcher cannot read its buttons; games may still read it through SDL",
        .lowBattery: "%@ is at %d%%",
        .lowBatteryDetail: "Charge it: a nearly empty controller drops its connection",
        .steamRunning: "Steam is running",
        .steamRunningDetail: "If the controller moves the pointer or presses twice, turn off Steam's controller support (Steam → Settings → Controller) or quit Steam",
        .testTitle: "Controller Test",
        .testHoldToLeave: "Hold %@ to leave",
        .testLeave: "Leave",
        .testNoPad: "Connect a controller to test it",
        .testSticks: "Sticks",
        .testTriggers: "Triggers",
        .vibrated: "Vibrating %@",
        .noVibration: "%@ cannot vibrate here",
        .connected: "%@ connected",
        .disconnected: "%@ disconnected",
    ]

    static let turkish: [Key: String] = [
        .title: "Kumandalar",
        .noneConnected: "Bağlı kumanda yok",
        .noneConnectedDetail: "USB kabloyla tak ya da Bluetooth ile eşle; aşağıdaki sorun giderici neye bakılacağını söyler",
        .playerOne: "Oyuncu 1",
        .testInputs: "Tuşları ve Çubukları Dene",
        .testInputsDetail: "Her tuş, iki çubuk ve tetikler, canlı",
        .testVibration: "Titreşimi Dene",
        .testVibrationDetail: "Oyuncu 1'in kumandasında birkaç güçlü titreşim",
        .light: "Işık Çubuğu",
        .lightDetail: "DualSense ve DualShock 4, başlatıcı öndeyken; oyunlar kendi rengini seçer",
        .lightTheme: "Tema Rengi", .lightBlue: "Mavi", .lightRed: "Kırmızı", .lightGreen: "Yeşil", .lightPurple: "Mor",
        .lightPink: "Pembe", .lightOrange: "Turuncu", .lightWhite: "Beyaz", .lightOff: "Kapalı",
        .confirm: "Onay Tuşu",
        .confirmDetail: "Japon konsollarındaki gibi Daire onaylar, Çarpı geri döner; ipuçları da değişir",
        .confirmCross: "✕ Çarpı", .confirmCircle: "○ Daire",
        .deadzone: "Çubuk Ölü Bölgesi",
        .deadzoneDetail: "Duran çubuğun kayması yok sayılır; başlatıcıda ve kendi ölü bölgesi olmayan oyunlarda",
        .usb: "USB", .bluetooth: "Bluetooth", .connectionUnknown: "Bağlı",
        .battery: "%%%d", .batteryAbout: "yaklaşık %%%d", .charging: "şarj oluyor", .generic: "Kumanda",
        .troubleshoot: "Sorun Giderme",
        .allGood: "Engel yok",
        .allGoodDetail: "Başlatıcı bağlı her kumandayı okuyor; oyunlar onları SDL ile okur",
        .noControllers: "macOS hiç kumanda görmüyor",
        .noControllersDetail: "Ne USB'de ne Bluetooth'ta. Aşağıdakilere bak, sonra PS, Xbox ya da Home tuşuna bas",
        .usbCable: "USB: veri taşıyan bir kablo",
        .usbCableDetail: "Çoğu kablo yalnızca şarj eder. Kumandanın kendi kablosunu ya da dosya aktardığını bildiğin bir kabloyu doğrudan Mac'e tak",
        .bluetoothPairing: "Bluetooth: Sistem Ayarları'nda eşle",
        .bluetoothPairingDetail: "DualSense ve DualShock 4: ışık yanıp sönene dek PS ile Create'e (Share) basılı tut. Xbox: eşleme tuşuna basılı tut. Switch Pro: sync tuşuna basılı tut. Sonra Sistem Ayarları → Bluetooth → Bağlan",
        .dualShock3: "DualShock 3: yalnızca USB ile",
        .dualShock3Detail: "macOS DualShock 3'ü Bluetooth ile eşleyemez. USB kabloyla tak ve PS'e bas: başlatıcı onu kendisi okur",
        .unmapped: "%@ için macOS'ta düzen yok",
        .unmappedDetail: "macOS onu listeliyor ama başlatıcı tuşlarını okuyamıyor; oyunlar SDL ile yine de okuyabilir",
        .lowBattery: "%@ şarjı %%%d",
        .lowBatteryDetail: "Şarj et: bitmek üzere olan kumandanın bağlantısı kopar",
        .steamRunning: "Steam açık",
        .steamRunningDetail: "Kumanda imleci oynatıyor ya da iki kez basıyorsa Steam'in kumanda desteğini kapat (Steam → Ayarlar → Kumanda) ya da Steam'den çık",
        .testTitle: "Kumanda Testi",
        .testHoldToLeave: "Çıkmak için %@ basılı tut",
        .testLeave: "Çık",
        .testNoPad: "Denemek için bir kumanda bağla",
        .testSticks: "Çubuklar",
        .testTriggers: "Tetikler",
        .vibrated: "%@ titreşiyor",
        .noVibration: "%@ burada titreşemiyor",
        .connected: "%@ bağlandı",
        .disconnected: "%@ ayrıldı",
    ]
}
