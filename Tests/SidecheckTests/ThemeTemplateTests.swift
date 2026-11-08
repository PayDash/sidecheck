import XCTest
@testable import Sidecheck

/// Template guard for the theme system: adding a ThemeID case without
/// completing its spec fails here instead of surfacing as a runtime wart.
@MainActor // WallpaperStore.defaultSpec is a MainActor static
final class ThemeTemplateTests: XCTestCase {
    func testEveryThemeHasACompleteSpec() {
        for theme in ThemeID.allCases {
            let spec = theme.spec
            XCTAssertEqual(spec.id, theme, "\(theme.rawValue): spec switch out of sync")
            XCTAssertFalse(theme.displayName.isEmpty, "\(theme.rawValue): missing displayName")
            XCTAssertGreaterThan(spec.frameSize.width, 0, "\(theme.rawValue): bad frameSize")
            XCTAssertGreaterThan(spec.frameSize.height, 0, "\(theme.rawValue): bad frameSize")
            XCTAssertGreaterThan(spec.panelRadius, 0, "\(theme.rawValue): bad panelRadius")
        }
    }

    func testMaxHomeSlotsStayWithinConfigRange() {
        for theme in ThemeID.allCases {
            let slots = theme.spec.maxHomeSlots
            XCTAssertTrue(Config.slotCountRange.contains(slots),
                          "\(theme.rawValue): maxHomeSlots \(slots) outside \(Config.slotCountRange)")
        }
    }

    func testDefaultBackgroundIsValidKind() {
        for theme in ThemeID.allCases {
            let kind = theme.spec.defaultBackground
            XCTAssertTrue(BackgroundKind.allCases.contains(kind),
                          "\(theme.rawValue): defaultBackground \(kind) is not a real kind")
        }
    }

    func testRawValuesRoundTrip() {
        for theme in ThemeID.allCases {
            XCTAssertEqual(ThemeID(rawValue: theme.rawValue), theme,
                           "\(theme.rawValue): restore path would fall back to liquidGlass")
        }
    }

    func testWallpaperDefaultSpecUsesThemeDeclaration() {
        for theme in ThemeID.allCases {
            XCTAssertEqual(WallpaperStore.defaultSpec(for: theme).kind, theme.spec.defaultBackground,
                           "\(theme.rawValue): defaultSpec drifted from the spec declaration")
        }
    }
}
