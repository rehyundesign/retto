import AppKit
import Foundation

/// A clean checkout must build all remaining skins, including their individual frame layers.
func runAllSkinsSelfTest() -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let results = PetSkin.allCases.map { skin in
        ["skin": skin.rawValue, "available": skin.isAvailable] as [String: Any]
    }
    let publicSkins = PetSkin.allCases.filter { !$0.isPersonal }
    let available = publicSkins.allSatisfy { $0.isAvailable }
    let resourcesOK = available && JeanneSkin.validate() && JeanneSkin.validateEffects()
        && PichiSkin.validate() && ChocolatHeart.validate() && hanaSkinSelfTest()
        && AmuRanFrames.hasAllFrames
    let ok = PetSkin.allCases.count == 14 && available && resourcesOK
    let report: [String: Any] = ["ok": ok, "skinCount": PetSkin.allCases.count, "publicSkinCount": publicSkins.count, "skins": results,
                               "completeFrameResources": resourcesOK]
    guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return 1 }
    print(json)
    return ok ? 0 : 1
}
