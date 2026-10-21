// Display hardware access for the Displays widget (2026-10-20). Findings behind each choice:
// docs/displays.md (read-only probe on Mac14,9 / macOS 26.5.2 with the built-in display and two
// DELL P3225QE over USB-C).
//   - Displays: NSScreen (name) + CGDirectDisplayID (built-in flag, vendor / model / serial).
//   - Built-in brightness: the public path does not work on Apple Silicon: there is no
//     IODisplayConnect service, IODisplayGetFloatParameter on AppleARMBacklight returns
//     kIOReturnUnsupported, and AppleARMBacklight's IODisplayParameters "brightness" stays at
//     32768/65536 whatever the slider says. DisplayServices.framework (private, resolved with
//     dlsym) reads the value Control Center shows; the registry value is only a fallback.
//   - External monitors: DCPAVServiceProxy ("Location" = "External") paired with its framebuffer
//     (IOMobileFramebufferShim / AppleCLCD2) by the "dispextN" node name, then with the
//     CGDirectDisplayID by vendor / product / serial from DisplayAttributes.ProductAttributes.
import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.graphics

struct DisplayInfo: Identifiable, Hashable, Sendable {
    var id: CGDirectDisplayID
    var name: String
    var isBuiltIn: Bool
    var isMain: Bool
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32

    /// Stable across reconnects (the display ID is not): used for the per-display settings.
    var key: String { isBuiltIn ? "builtin" : "\(vendor)-\(model)-\(serial)" }

    var systemImage: String { isBuiltIn ? "laptopcomputer" : "display" }
}

/// The hardware the service talks to (`SystemDisplayHardware`; tests use a fake).
protocol DisplayHardware: AnyObject, Sendable {
    /// Connected displays (main actor: reads NSScreen).
    @MainActor func displays() -> [DisplayInfo]
    /// Built-in panel brightness 0…1, nil when unreadable. Called on the service's I/O queue.
    func builtInBrightness(_ display: CGDirectDisplayID) -> Double?
    /// Whether `setBuiltInBrightness` can work for this display.
    func canSetBuiltInBrightness(_ display: CGDirectDisplayID) -> Bool
    func setBuiltInBrightness(_ value: Double, display: CGDirectDisplayID) -> Bool
    /// DDC/CI channels to the external monitors, by display ID. Called on the I/O queue.
    func ddcChannels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCChannel]
    /// Short description of the built-in backend (settings pane).
    var builtInBackendName: String { get }
    /// The built-in value comes from a source that may not follow the user's setting.
    var builtInBrightnessIsApproximate: Bool { get }
    /// DDC/CI can be used on this Mac at all (Apple Silicon IOAVService).
    var supportsDDC: Bool { get }
}

final class SystemDisplayHardware: DisplayHardware, @unchecked Sendable {
    @MainActor func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            return DisplayInfo(id: id, name: screen.localizedName,
                               isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0,
                               vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                               serial: CGDisplaySerialNumber(id))
        }
    }

    var builtInBackendName: String {
        DisplayServicesBacklight.isAvailable ? "DisplayServices" : "IORegistry (AppleARMBacklight)"
    }

    var builtInBrightnessIsApproximate: Bool { !DisplayServicesBacklight.isAvailable }

    var supportsDDC: Bool { IOAVServiceAPI.isAvailable }

    func builtInBrightness(_ display: CGDirectDisplayID) -> Double? {
        DisplayServicesBacklight.brightness(display) ?? RegistryBacklight.brightness()
    }

    func canSetBuiltInBrightness(_ display: CGDirectDisplayID) -> Bool {
        DisplayServicesBacklight.canChange(display)
    }

    func setBuiltInBrightness(_ value: Double, display: CGDirectDisplayID) -> Bool {
        DisplayServicesBacklight.setBrightness(value, display: display)
    }

    func ddcChannels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCChannel] {
        let endpoints = DDCServiceLocator.endpoints()
        defer { endpoints.forEach { IOObjectRelease($0.proxy) } }
        let pairs = DisplayMatcher.match(displays: displays.filter { !$0.isBuiltIn }.map(DisplayIdentity.init),
                                         endpoints: endpoints.map(\.identity))
        var result: [CGDirectDisplayID: DDCChannel] = [:]
        for (displayID, index) in pairs {
            if let t = IOAVServiceDDCTransport(proxy: endpoints[index].proxy) {
                result[displayID] = DDCChannel(transport: t)
            }
        }
        return result
    }
}

// MARK: - Built-in backlight

/// DisplayServices.framework (private): the getter returns the Control Center slider value.
enum DisplayServicesBacklight {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias Can = @convention(c) (CGDirectDisplayID) -> Bool

    private struct Functions {
        var get: Get
        var set: SetFn?
        var can: Can?
    }

    private static let functions: Functions? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let g = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return Functions(get: unsafeBitCast(g, to: Get.self),
                         set: dlsym(h, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) },
                         can: dlsym(h, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: Can.self) })
    }()

    static var isAvailable: Bool { functions != nil }

    static func brightness(_ display: CGDirectDisplayID) -> Double? {
        guard let f = functions else { return nil }
        var v: Float = -1
        guard f.get(display, &v) == 0, v.isFinite, (0...1).contains(v) else { return nil }
        return Double(v)
    }

    static func canChange(_ display: CGDirectDisplayID) -> Bool {
        guard let f = functions, f.set != nil else { return false }
        return f.can?(display) ?? true
    }

    static func setBrightness(_ value: Double, display: CGDirectDisplayID) -> Bool {
        guard let set = functions?.set, value.isFinite else { return false }
        return set(display, Float(min(max(value, 0), 1))) == 0
    }
}

/// Public IOKit fallback: AppleARMBacklight's IODisplayParameters. On macOS 26.5 the "brightness"
/// entry did not follow the user's setting (docs/displays.md §2), so this is only used when
/// DisplayServices is missing, and the widget marks the value as approximate.
enum RegistryBacklight {
    struct Parameters: Equatable, Sendable {
        var brightness: Double?
        var milliNits: Int?
    }

    static func parameters() -> Parameters? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let params = IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return Parameters(brightness: fraction(params["brightness"]),
                          milliNits: (params["BrightnessMilliNits"] as? [String: Any])?["value"] as? Int)
    }

    static func brightness() -> Double? { parameters()?.brightness }

    /// `{min, max, value}` → (value − min) / (max − min).
    static func fraction(_ entry: Any?) -> Double? {
        guard let d = entry as? [String: Any],
              let value = d["value"] as? Int, let lo = d["min"] as? Int, let hi = d["max"] as? Int, hi > lo
        else { return nil }
        return min(max(Double(value - lo) / Double(hi - lo), 0), 1)
    }
}

// MARK: - DDC service discovery

/// What identifies a display on both sides of the pairing (pure; tested).
struct DisplayIdentity: Equatable, Hashable, Sendable {
    var displayID: CGDirectDisplayID
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32

    init(displayID: CGDirectDisplayID = 0, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.displayID = displayID
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }

    init(_ info: DisplayInfo) {
        self.init(displayID: info.id, vendor: info.vendor, model: info.model, serial: info.serial)
    }
}

struct DDCEndpoint {
    /// Retained DCPAVServiceProxy (released by the caller).
    var proxy: io_service_t
    /// "dispext0", "dispext1", …
    var node: String
    var productName: String?
    var identity: DisplayIdentity
}

enum DDCServiceLocator {
    /// External DCPAVServiceProxy services with the identity of their framebuffer's display.
    static func endpoints() -> [DDCEndpoint] {
        var framebuffers: [String: (name: String?, identity: DisplayIdentity)] = [:]
        for cls in ["IOMobileFramebufferShim", "AppleCLCD2"] {
            forEachService(cls) { s in
                guard let node = parentName(s).map(nodeName(ofFramebufferParent:)),
                      let attrs = property(s, "DisplayAttributes") as? [String: Any],
                      let product = attrs["ProductAttributes"] as? [String: Any] else { return }
                framebuffers[node] = (product["ProductName"] as? String,
                                      DisplayIdentity(vendor: uint32(product["LegacyManufacturerID"]),
                                                      model: uint32(product["ProductID"]),
                                                      serial: uint32(product["SerialNumber"])))
            }
        }
        var result: [DDCEndpoint] = []
        forEachService("DCPAVServiceProxy") { s in
            guard property(s, "Location") as? String == "External",
                  let node = parentName(s).map(nodeName(ofProxyParent:)),
                  let fb = framebuffers[node] else { return }
            IOObjectRetain(s)
            result.append(DDCEndpoint(proxy: s, node: node, productName: fb.name, identity: fb.identity))
        }
        return result.sorted { $0.node < $1.node }
    }

    /// "dispext0@88000000" → "dispext0".
    static func nodeName(ofFramebufferParent name: String) -> String {
        String(name.split(separator: "@", maxSplits: 1).first ?? Substring(name))
    }

    /// "dispext0:dcpav-service-epic:0" → "dispext0".
    static func nodeName(ofProxyParent name: String) -> String {
        String(name.split(separator: ":", maxSplits: 1).first ?? Substring(name))
    }

    private static func forEachService(_ cls: String, _ body: (io_service_t) -> Void) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        while case let s = IOIteratorNext(it), s != 0 {
            body(s)
            IOObjectRelease(s)
        }
    }

    private static func property(_ s: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func parentName(_ s: io_registry_entry_t) -> String? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(s, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        var buf = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(parent, &buf) == KERN_SUCCESS else { return nil }
        return String(cString: buf)
    }

    private static func uint32(_ v: Any?) -> UInt32 {
        (v as? NSNumber).map { UInt32(truncatingIfNeeded: $0.int64Value) } ?? 0
    }
}

enum DisplayMatcher {
    /// Pairs displays with DDC endpoints (index into `endpoints`): first by vendor + model +
    /// serial, then the remaining ones by vendor + model in order (identical monitors that report
    /// serial 0), so each endpoint is used at most once.
    static func match(displays: [DisplayIdentity], endpoints: [DisplayIdentity]) -> [CGDirectDisplayID: Int] {
        var result: [CGDirectDisplayID: Int] = [:]
        var used = Set<Int>()
        for d in displays {
            if let i = endpoints.indices.first(where: { !used.contains($0)
                && endpoints[$0].vendor == d.vendor && endpoints[$0].model == d.model
                && endpoints[$0].serial == d.serial && d.serial != 0 }) {
                result[d.displayID] = i
                used.insert(i)
            }
        }
        for d in displays where result[d.displayID] == nil {
            if let i = endpoints.indices.first(where: { !used.contains($0)
                && endpoints[$0].vendor == d.vendor && endpoints[$0].model == d.model }) {
                result[d.displayID] = i
                used.insert(i)
            }
        }
        return result
    }
}
