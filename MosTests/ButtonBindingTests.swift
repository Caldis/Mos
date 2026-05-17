import XCTest
@testable import Mos_Debug

private final class ShortcutMenuTestTarget: NSObject {
    @objc func noop(_ sender: Any?) {}
}

final class ButtonBindingTests: XCTestCase {

    private func makeResolvedPresentation(
        shortcut: SystemShortcut.Shortcut? = nil,
        customBindingName: String? = nil,
        isRecording: Bool = false
    ) -> ActionPresentation {
        ActionDisplayResolver().resolve(
            shortcut: shortcut,
            customBindingName: customBindingName,
            isRecording: isRecording
        )
    }

    private func makeButtonCell(
        binding: ButtonBinding,
        onOpenTargetSelectionRequested: @escaping () -> Void = {}
    ) -> ButtonTableCellView {
        let cell = ButtonTableCellView(frame: NSRect(x: 0, y: 0, width: 420, height: 44))
        let keyContainer = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 44))
        let actionButton = NSPopUpButton(frame: NSRect(x: 180, y: 8, width: 180, height: 28), pullsDown: false)

        cell.keyDisplayContainerView = keyContainer
        cell.actionPopUpButton = actionButton
        cell.addSubview(keyContainer)
        cell.addSubview(actionButton)

        cell.configure(
            with: binding,
            onShortcutSelected: { _ in },
            onCustomShortcutRecorded: { _ in },
            onOpenTargetSelectionRequested: onOpenTargetSelectionRequested,
            onDeleteRequested: {}
        )

        return cell
    }

    private func flushMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private func advanceMainRunLoop(by interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    private func makeActionPopupButton() -> NSPopUpButton {
        let actionButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 28), pullsDown: false)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        actionButton.menu = menu
        return actionButton
    }

    func testHoverIntentPopoverControllerHandlesCloseCallback() {
        let controller = HoverIntentPopoverController()

        XCTAssertTrue(controller is NSPopoverDelegate)
        XCTAssertTrue(controller.responds(to: #selector(NSPopoverDelegate.popoverDidClose(_:))))
    }

    func testHoverIntentPopoverCloseCallbackClearsStoredPopoverReference() {
        let controller = HoverIntentPopoverController()
        let popover = NSPopover()

        controller.testingInstallPopover(popover)
        XCTAssertTrue((popover.delegate as AnyObject?) === controller)
        XCTAssertTrue(controller.testingHasPopover)

        controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(controller.testingHasPopover)
    }

    func testHoverIntentGeometryKeepsPointerInsideVerticalCorridor() {
        let source = NSRect(x: 100, y: 100, width: 28, height: 28)
        let popover = NSRect(x: 60, y: 170, width: 140, height: 90)

        XCTAssertTrue(HoverIntentPopoverGeometry.shouldKeepOpen(
            pointer: NSPoint(x: 116, y: 150),
            sourceFrame: source,
            popoverFrame: popover,
            corridorPadding: 10
        ))
    }

    func testHoverIntentGeometryClosesWhenPointerLeavesCorridor() {
        let source = NSRect(x: 100, y: 100, width: 28, height: 28)
        let popover = NSRect(x: 60, y: 170, width: 140, height: 90)

        XCTAssertFalse(HoverIntentPopoverGeometry.shouldKeepOpen(
            pointer: NSPoint(x: 225, y: 150),
            sourceFrame: source,
            popoverFrame: popover,
            corridorPadding: 10
        ))
    }

    func testHoverIntentGeometryKeepsPointerInsidePopoverFrame() {
        let source = NSRect(x: 100, y: 100, width: 28, height: 28)
        let popover = NSRect(x: 60, y: 170, width: 140, height: 90)

        XCTAssertTrue(HoverIntentPopoverGeometry.shouldKeepOpen(
            pointer: NSPoint(x: 120, y: 210),
            sourceFrame: source,
            popoverFrame: popover,
            corridorPadding: 10
        ))
    }

    private func opaqueBounds(in image: NSImage) -> NSRect? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        var minX = rep.pixelsWide
        var minY = rep.pixelsHigh
        var maxX = -1
        var maxY = -1

        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y),
                      color.alphaComponent > 0.05 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let scaleX = CGFloat(rep.pixelsWide) / image.size.width
        let scaleY = CGFloat(rep.pixelsHigh) / image.size.height
        return NSRect(
            x: CGFloat(minX) / scaleX,
            y: CGFloat(minY) / scaleY,
            width: CGFloat(maxX - minX + 1) / scaleX,
            height: CGFloat(maxY - minY + 1) / scaleY
        )
    }

    private func assertUsesDefaultAlignmentRect(_ image: NSImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            NSEqualRects(image.alignmentRect, NSRect(origin: .zero, size: image.size)),
            "Expected default alignmentRect, got \(image.alignmentRect) for image size \(image.size)",
            file: file,
            line: line
        )
    }

    private func assertHasTrailingVisiblePadding(
        _ image: NSImage,
        minimumPadding: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let bounds = opaqueBounds(in: image) else {
            return XCTFail("Expected image to contain visible pixels", file: file, line: line)
        }

        let trailingPadding = image.size.width - bounds.maxX
        XCTAssertGreaterThanOrEqual(
            trailingPadding,
            minimumPadding,
            "Expected at least \(minimumPadding)pt trailing padding after visible content, got \(trailingPadding)pt for image size \(image.size) and bounds \(bounds)",
            file: file,
            line: line
        )
    }

    private func averageVisibleLuminance(in image: NSImage) -> CGFloat? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        var weightedTotal: CGFloat = 0
        var totalWeight: CGFloat = 0

        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let sourceColor = rep.colorAt(x: x, y: y),
                      sourceColor.alphaComponent > 0.05,
                      let color = sourceColor.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                weightedTotal += luminance * alpha
                totalWeight += alpha
            }
        }

        guard totalWeight > 0 else { return nil }
        return weightedTotal / totalWeight
    }

    private func keyComboBadgeWidthWithoutTrailingSafetyPadding(components: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let plusFont = NSFont.systemFont(ofSize: 9)
        let badgeHeight: CGFloat = 17
        let hPadding: CGFloat = 5
        let plusSpacing: CGFloat = 3
        let iconWidth: CGFloat
        if #available(macOS 11.0, *) {
            let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            let keyboardImage = symbol?.withSymbolConfiguration(config) ?? symbol
            iconWidth = (keyboardImage?.size.width ?? 0) + 4
        } else {
            iconWidth = 0
        }

        var totalWidth = iconWidth
        for (index, component) in components.enumerated() {
            let textSize = (component as NSString).size(withAttributes: [.font: font])
            totalWidth += max(textSize.width + hPadding * 2, badgeHeight)
            if index > 0 {
                let plusSize = ("+" as NSString).size(withAttributes: [.font: plusFont])
                totalWidth += plusSpacing * 2 + plusSize.width
            }
        }
        return ceil(totalWidth)
    }

    func testPrepareCustomCache_regularKey() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:1048576"
        )
        binding.prepareCustomCache()
        XCTAssertEqual(binding.cachedCustomCode, 40)
        XCTAssertEqual(binding.cachedCustomModifiers, 1048576)
    }

    func testPrepareCustomCache_modifierKey_stripsRedundantFlag() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::56:131072"
        )
        binding.prepareCustomCache()
        XCTAssertEqual(binding.cachedCustomCode, 56)
        XCTAssertEqual(binding.cachedCustomModifiers, 0)
    }

    func testPrepareCustomCache_nonCustomBinding() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "missionControl"
        )
        binding.prepareCustomCache()
        XCTAssertNil(binding.cachedCustomCode)
        XCTAssertNil(binding.cachedCustomModifiers)
    }

    func testPrepareCustomCache_invalidFormat() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::abc:xyz"
        )
        binding.prepareCustomCache()
        XCTAssertNil(binding.cachedCustomCode)
        XCTAssertNil(binding.cachedCustomModifiers)
    }

    func testPrepareCustomCache_masksIrrelevantModifierFlags() {
        let rawModifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue) | (1 << 24)
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::21:\(rawModifiers)"
        )

        binding.prepareCustomCache()

        XCTAssertEqual(binding.cachedCustomCode, 21)
        XCTAssertEqual(
            binding.cachedCustomModifiers,
            UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        )
    }

    func testPrepareCustomCache_typedMouseBindingPreservesMouseType() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "custom::mouse:3:0"
        )

        binding.prepareCustomCache()

        XCTAssertEqual(binding.cachedCustomType, .mouse)
        XCTAssertEqual(binding.cachedCustomCode, 3)
        XCTAssertEqual(binding.cachedCustomModifiers, 0)
    }

    func testPrepareCustomCache_legacyHighCodeBindingInfersMouseType() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "custom::1006:0"
        )

        binding.prepareCustomCache()

        XCTAssertEqual(binding.cachedCustomType, .mouse)
        XCTAssertEqual(binding.cachedCustomCode, 1006)
        XCTAssertEqual(binding.cachedCustomModifiers, 0)
    }

    func testNormalizedCustomBindingName_encodesMouseType() {
        XCTAssertEqual(
            ButtonBinding.normalizedCustomBindingName(type: .mouse, code: 3, modifiers: 0),
            "custom::mouse:3:0"
        )
    }

    func testInit_withCreatedAt_preservesTimestamp() {
        let pastDate = Date(timeIntervalSince1970: 1000000)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "test",
            createdAt: pastDate
        )
        XCTAssertEqual(binding.createdAt, pastDate)
    }

    func testInit_defaultCreatedAt_usesNow() {
        let before = Date()
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "test"
        )
        let after = Date()
        XCTAssertGreaterThanOrEqual(binding.createdAt, before)
        XCTAssertLessThanOrEqual(binding.createdAt, after)
    }

    func testCodableRoundtrip_preservesFields() {
        let original = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::56:0"
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.systemShortcutName, "custom::56:0")
        XCTAssertNil(decoded.cachedCustomCode)
    }

    func testEquatable_ignoresTransientCache() {
        var a = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::56:0"
        )
        let b = a
        a.prepareCustomCache()
        XCTAssertEqual(a, b)
    }

    func testPredefinedModifierShortcut_matchesEquivalentCustomBinding() {
        XCTAssertEqual(
            SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::56:0")?.identifier,
            "modifierShift"
        )
        XCTAssertEqual(
            SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::56:131072")?.identifier,
            "modifierShift"
        )
        XCTAssertEqual(
            SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::58:524288")?.identifier,
            "modifierOption"
        )
        XCTAssertNil(SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::58:131072"))
    }

    func testDisplayShortcut_matchesUniqueCustomBindingEquivalent() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        XCTAssertEqual(
            SystemShortcut.displayShortcut(matchingBindingName: "custom::21:\(modifiers)")?.identifier,
            "screenshotSelection"
        )
    }

    func testDisplayShortcut_matchesUniqueCustomBindingEquivalentWithIrrelevantFlags() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue) | (1 << 24)
        XCTAssertEqual(
            SystemShortcut.displayShortcut(matchingBindingName: "custom::21:\(modifiers)")?.identifier,
            "screenshotSelection"
        )
    }

    func testDisplayShortcut_returnsNilForAmbiguousCustomBindingEquivalent() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.rawValue)
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: "custom::34:\(modifiers)"))
    }

    func testDisplayShortcut_doesNotMatchMosScrollPlaceholderCode() {
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: "custom::65532:0"))
    }

    func testDisplayShortcut_matchesTypedMouseBackCustomBinding() {
        XCTAssertEqual(
            SystemShortcut.displayShortcut(matchingBindingName: "custom::mouse:3:0")?.identifier,
            "mouseBackClick"
        )
    }

    func testActionDisplayResolver_prioritizesRecordingPromptOverExistingShortcut() {
        let presentation = makeResolvedPresentation(
            shortcut: SystemShortcut.screenshotSelection,
            customBindingName: "custom::1007:0",
            isRecording: true
        )

        XCTAssertEqual(presentation.kind, .recordingPrompt)
        XCTAssertEqual(presentation.title, NSLocalizedString("custom-recording-prompt", comment: ""))
        XCTAssertTrue(presentation.badgeComponents.isEmpty)
        XCTAssertNil(presentation.brand)
    }

    func testActionDisplayResolver_upgradesRecognizedCustomBindingToNamedAction() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        let presentation = makeResolvedPresentation(customBindingName: "custom::21:\(modifiers)")

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, SystemShortcut.screenshotSelection.localizedName)
        XCTAssertEqual(presentation.brand?.name, nil)
    }

    func testActionDisplayResolver_upgradesTypedMouseBackCustomBindingToNamedAction() {
        let presentation = makeResolvedPresentation(customBindingName: "custom::mouse:3:0")

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, SystemShortcut.mouseBackClick.localizedName)
    }

    func testActionDisplayResolver_rendersTypedMouseCustomBindingAsMouseBadge() {
        let presentation = makeResolvedPresentation(customBindingName: "custom::mouse:5:0")

        XCTAssertEqual(presentation.kind, .keyCombo)
        XCTAssertEqual(presentation.badgeComponents, ["🖱5"])
    }

    func testInputEventUsesSemanticNamesForStandardMouseBackAndForwardButtons() {
        let back = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )
        let forward = InputEvent(
            type: .mouse,
            code: 4,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertEqual(back.displayComponents, ["🖱️ Back Button"])
        XCTAssertEqual(forward.displayComponents, ["🖱️ Forward Button"])
    }

    func testRecordedEventDisplayComponentsRefreshLegacyStandardMouseButtonNames() {
        let back = RecordedEvent(
            type: .mouse,
            code: 3,
            modifiers: 0,
            displayComponents: ["🖱4"],
            deviceFilter: nil
        )
        let forward = RecordedEvent(
            type: .mouse,
            code: 4,
            modifiers: UInt(CGEventFlags.maskShift.rawValue),
            displayComponents: ["⇧", "🖱5"],
            deviceFilter: nil
        )

        XCTAssertEqual(back.displayComponents, ["🖱️ Back Button"])
        XCTAssertEqual(forward.displayComponents, ["⇧", "🖱️ Forward Button"])
    }

    func testRecordedEventDecodesLegacyDisplayComponentsButIgnoresStoredPresentation() throws {
        let modifiers = UInt(CGEventFlags.maskShift.rawValue)
        let json = """
        {
            "type": "mouse",
            "code": 3,
            "modifiers": \(modifiers),
            "displayComponents": ["Legacy Back"],
            "deviceFilter": null
        }
        """

        let event = try JSONDecoder().decode(RecordedEvent.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(event.displayComponents, ["⇧", "🖱️ Back Button"])
    }

    func testRecordedEventEncodingOmitsDisplayComponents() throws {
        let event = RecordedEvent(
            type: .mouse,
            code: 3,
            modifiers: 0,
            displayComponents: ["Legacy Back"],
            deviceFilter: nil
        )

        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["displayComponents"])
        XCTAssertEqual(object["type"] as? String, "mouse")
        XCTAssertEqual(object["code"] as? Int, 3)
    }

    func testActionDisplayResolver_upgradesSingleLogiCustomBindingToBrandedNamedAction() {
        let presentation = makeResolvedPresentation(customBindingName: "custom::1007:0")

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, "Forward Button")
        XCTAssertTrue(presentation.badgeComponents.isEmpty)
        XCTAssertEqual(presentation.brand?.name, BrandTagConfig.logi.name)
    }

    func testActionTagConfig_mosUsesNeonLogoPalette() {
        let tag = BrandTagConfig.mos
        let bgColor = tag.bgColor.usingColorSpace(.deviceRGB)
        let textColor = tag.textColor.usingColorSpace(.deviceRGB)
        let innerHighlightColor = tag.innerHighlightColor?.usingColorSpace(.deviceRGB)
        let gradientColors = tag.gradientColors?.compactMap { $0.usingColorSpace(.deviceRGB) }

        XCTAssertEqual(tag.name, "Mos")
        XCTAssertLessThan(bgColor?.redComponent ?? 1, 0.15)
        XCTAssertLessThan(bgColor?.greenComponent ?? 1, 0.18)
        XCTAssertLessThan(bgColor?.blueComponent ?? 1, 0.35)
        XCTAssertGreaterThan(textColor?.redComponent ?? 0, 0.8)
        XCTAssertGreaterThan(textColor?.greenComponent ?? 0, 0.9)
        XCTAssertGreaterThan(textColor?.blueComponent ?? 0, 0.95)
        XCTAssertNil(tag.borderColor)
        XCTAssertNotNil(innerHighlightColor)
        XCTAssertGreaterThan(innerHighlightColor?.blueComponent ?? 0, 0.8)
        XCTAssertLessThan(innerHighlightColor?.alphaComponent ?? 1, 0.25)
        XCTAssertEqual(gradientColors?.count, 2)
        XCTAssertGreaterThan(gradientColors?.first?.blueComponent ?? 0, 0.35)
        XCTAssertGreaterThan(gradientColors?.last?.blueComponent ?? 0, 0.55)
        XCTAssertGreaterThan(gradientColors?.last?.redComponent ?? 0, 0.35)
    }

    func testActionDisplayResolver_mosScrollShortcutUsesReusableMosTag() {
        let presentation = makeResolvedPresentation(shortcut: SystemShortcut.mosScrollDash)

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, SystemShortcut.mosScrollDash.localizedName)
        XCTAssertEqual(presentation.tag?.name, BrandTagConfig.mos.name)
        XCTAssertEqual(presentation.brand?.name, BrandTagConfig.mos.name)
    }

    func testConfiguredButtonCell_showsBrandedNamedDisplayForSingleLogiCustomBinding() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::1007:0"
        )

        let cell = makeButtonCell(binding: binding)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, "Forward Button")
        XCTAssertNotNil(cell.actionPopUpButton.menu?.items.first?.image)
    }

    func testActionDisplayResolver_returnsUnboundWhenNoActionExists() {
        let presentation = makeResolvedPresentation()

        XCTAssertEqual(presentation.kind, .unbound)
        XCTAssertEqual(presentation.title, NSLocalizedString("unbound", comment: ""))
    }

    func testActionDisplayRenderer_rendersRecordingPromptWithoutResidualImage() {
        let popupButton = makeActionPopupButton()
        let presentation = ActionPresentation(
            kind: .recordingPrompt,
            title: NSLocalizedString("custom-recording-prompt", comment: ""),
            symbolName: nil,
            badgeComponents: [],
            brand: nil
        )

        ActionDisplayRenderer().render(presentation, into: popupButton)

        XCTAssertEqual(popupButton.menu?.items.first?.title, presentation.title)
        XCTAssertNil(popupButton.menu?.items.first?.image)
    }

    func testActionDisplayRenderer_prefixesBrandTagForNamedActionSymbol() {
        let brandedPopup = makeActionPopupButton()
        let plainPopup = makeActionPopupButton()
        let branded = ActionPresentation(
            kind: .namedAction,
            title: "Forward Button",
            symbolName: "chevron.forward",
            badgeComponents: [],
            brand: .logi
        )
        let plain = ActionPresentation(
            kind: .namedAction,
            title: "Forward Button",
            symbolName: "chevron.forward",
            badgeComponents: [],
            brand: nil
        )

        let renderer = ActionDisplayRenderer()
        renderer.render(branded, into: brandedPopup)
        renderer.render(plain, into: plainPopup)

        guard let brandedImage = brandedPopup.menu?.items.first?.image,
              let plainImage = plainPopup.menu?.items.first?.image else {
            return XCTFail("Expected both render paths to create placeholder images")
        }

        XCTAssertGreaterThan(brandedImage.size.width, plainImage.size.width)
    }

    func testActionDisplayRenderer_rendersKeyComboAsBadgeImage() {
        let popupButton = makeActionPopupButton()
        let presentation = ActionPresentation(
            kind: .keyCombo,
            title: "",
            symbolName: nil,
            badgeComponents: ["⇧ ⌘", "4"],
            brand: nil
        )

        ActionDisplayRenderer().render(presentation, into: popupButton)

        XCTAssertEqual(popupButton.menu?.items.first?.title, "")
        XCTAssertNotNil(popupButton.menu?.items.first?.image)
    }

    func testActionDisplayRenderer_keyComboButtonFaceKeepsMenuImageScale() {
        for badgeComponents in [
            ["⌃", "⌥", "⇧", "⌘"],
            ["⌥", "M"],
            ["⌃", "I"]
        ] {
            let popupButton = makeActionPopupButton()
            let presentation = ActionPresentation(
                kind: .keyCombo,
                title: "",
                symbolName: nil,
                badgeComponents: badgeComponents,
                brand: nil
            )

            ActionDisplayRenderer().render(presentation, into: popupButton)

            guard let placeholderImage = popupButton.menu?.items.first?.image,
                  let cell = popupButton.cell as? NSPopUpButtonCell,
                  let buttonFaceImage = cell.menuItem?.image else {
                return XCTFail("Expected key combo render path to create both menu and button-face images")
            }

            XCTAssertEqual(popupButton.menu?.items.first?.title, "")
            XCTAssertEqual(cell.menuItem?.title, "")
            assertUsesDefaultAlignmentRect(placeholderImage)
            assertUsesDefaultAlignmentRect(buttonFaceImage)
            XCTAssertEqual(buttonFaceImage.size.width, placeholderImage.size.width, accuracy: 0.01)
            XCTAssertEqual(buttonFaceImage.size.height, placeholderImage.size.height, accuracy: 0.01)
            let unpaddedWidth = keyComboBadgeWidthWithoutTrailingSafetyPadding(components: badgeComponents)
            XCTAssertGreaterThanOrEqual(buttonFaceImage.size.width - unpaddedWidth, 2)
            XCTAssertLessThanOrEqual(buttonFaceImage.size.width - unpaddedWidth, 4)
            assertHasTrailingVisiblePadding(placeholderImage, minimumPadding: 1.5)
            assertHasTrailingVisiblePadding(buttonFaceImage, minimumPadding: 1.5)

            guard let menuBounds = opaqueBounds(in: placeholderImage),
                  let buttonFaceBounds = opaqueBounds(in: buttonFaceImage) else {
                return XCTFail("Expected both menu and button-face images to contain visible pixels")
            }
            XCTAssertEqual(buttonFaceBounds.width, menuBounds.width, accuracy: 0.75)
            XCTAssertEqual(buttonFaceBounds.height, menuBounds.height, accuracy: 0.75)
        }
    }

    func testActionDisplayRenderer_keyComboUsesPopupButtonAppearanceWhenRasterizing() {
        guard #available(macOS 10.14, *),
              let darkAppearance = NSAppearance(named: .darkAqua),
              let lightAppearance = NSAppearance(named: .aqua) else {
            return
        }

        let previousCurrentAppearance = NSAppearance.current
        defer { NSAppearance.current = previousCurrentAppearance }

        let presentation = ActionPresentation(
            kind: .keyCombo,
            title: "",
            symbolName: nil,
            badgeComponents: ["⌃", "K"],
            brand: nil
        )

        let darkPopupButton = makeActionPopupButton()
        darkPopupButton.appearance = darkAppearance
        NSAppearance.current = lightAppearance
        ActionDisplayRenderer().render(presentation, into: darkPopupButton)

        let lightPopupButton = makeActionPopupButton()
        lightPopupButton.appearance = lightAppearance
        NSAppearance.current = darkAppearance
        ActionDisplayRenderer().render(presentation, into: lightPopupButton)

        guard let darkImage = (darkPopupButton.cell as? NSPopUpButtonCell)?.menuItem?.image,
              let lightImage = (lightPopupButton.cell as? NSPopUpButtonCell)?.menuItem?.image,
              let darkLuminance = averageVisibleLuminance(in: darkImage),
              let lightLuminance = averageVisibleLuminance(in: lightImage) else {
            return XCTFail("Expected keyCombo images with visible pixels")
        }

        XCTAssertGreaterThan(
            darkLuminance,
            lightLuminance + 0.2,
            "Expected keyCombo bitmap colors to follow the popup button appearance, not NSAppearance.current"
        )
    }

    func testButtonTableCellView_refreshesKeyComboImageWhenAppearanceChanges() {
        guard #available(macOS 10.14, *) else { return }

        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }

        guard let darkAppearance = NSAppearance(named: .darkAqua),
              let lightAppearance = NSAppearance(named: .aqua) else {
            return
        }

        NSApp.appearance = darkAppearance
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:1048576",
            isEnabled: true
        )
        let cell = makeButtonCell(binding: binding)
        cell.actionPopUpButton.appearance = darkAppearance
        cell.refreshActionDisplay()

        guard let darkImageData = (cell.actionPopUpButton.cell as? NSPopUpButtonCell)?
            .menuItem?
            .image?
            .tiffRepresentation else {
            return XCTFail("Expected keyCombo button face image before appearance change")
        }

        NSApp.appearance = lightAppearance
        cell.actionPopUpButton.appearance = lightAppearance
        cell.viewDidChangeEffectiveAppearance()
        advanceMainRunLoop(by: 0.15)

        guard let lightImageData = (cell.actionPopUpButton.cell as? NSPopUpButtonCell)?
            .menuItem?
            .image?
            .tiffRepresentation else {
            return XCTFail("Expected keyCombo button face image after appearance change")
        }

        XCTAssertNotEqual(darkImageData, lightImageData)
    }

    // MARK: - ActionPresentation openTarget

    func testActionDisplayResolver_returnsOpenTargetKindWhenPayloadProvided() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "",
            kind: .application
        )
        let presentation = ActionDisplayResolver().resolve(
            shortcut: nil,
            customBindingName: nil,
            isRecording: false,
            openTarget: payload
        )
        XCTAssertEqual(presentation.kind, .openTarget)
        // Title should be either the file's basename or app displayName — both acceptable.
        XCTAssertFalse(presentation.title.isEmpty)
    }

    func testActionDisplayResolver_openTargetStalePathProducesUnavailableTitle() {
        let payload = OpenTargetPayload(
            path: "/totally-fake-path-do-not-exist.app",
            bundleID: "com.does.not.exist",
            arguments: "",
            kind: .application
        )
        let presentation = ActionDisplayResolver().resolve(
            shortcut: nil,
            customBindingName: nil,
            isRecording: false,
            openTarget: payload
        )
        XCTAssertEqual(presentation.kind, .openTarget)
        XCTAssertTrue(
            presentation.title.contains(NSLocalizedString("open-target-placeholder-stale", comment: ""))
                || presentation.title.contains("totally-fake-path-do-not-exist"),
            "Stale path should produce either filename + (unavailable) suffix or just '(unavailable)'; got: \(presentation.title)"
        )
    }

    func testActionDisplayRenderer_rendersOpenTargetWithImage() {
        let popupButton = makeActionPopupButton()
        let stubImage = NSImage(size: NSSize(width: 16, height: 16))
        let presentation = ActionPresentation(
            kind: .openTarget,
            title: "Safari",
            symbolName: nil,
            image: stubImage,
            badgeComponents: [],
            brand: nil
        )

        ActionDisplayRenderer().render(presentation, into: popupButton)

        XCTAssertEqual(popupButton.menu?.items.first?.title, "Safari")
        XCTAssertNotNil(popupButton.menu?.items.first?.image)
    }

    func testBuildShortcutMenu_includesModifierCategoryWithSingleModifierShortcuts() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let modifierCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.modifierKeysCategory.category)
        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)

        guard let modifierIndex = menu.items.firstIndex(where: { $0.title == modifierCategoryName }),
              let mouseIndex = menu.items.firstIndex(where: { $0.title == mouseCategoryName }) else {
            return XCTFail("Expected modifier and mouse categories to exist in shortcut menu")
        }

        XCTAssertLessThan(modifierIndex, mouseIndex)

        let modifierItems = menu.items[modifierIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        }
        XCTAssertEqual(
            modifierItems,
            ["modifierShift", "modifierOption", "modifierControl", "modifierCommand", "modifierFn"]
        )
    }

    func testBuildShortcutMenu_placesMosMouseScrollBelowMouseButtons() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:)),
            showLogiActions: true
        )

        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)
        let mosCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mosMouseScrollCategory.category)
        let logiCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.logiActionsCategory.category)

        guard let mouseIndex = menu.items.firstIndex(where: { $0.title == mouseCategoryName }),
              let mosIndex = menu.items.firstIndex(where: { $0.title == mosCategoryName }),
              let logiIndex = menu.items.firstIndex(where: { $0.title == logiCategoryName }) else {
            return XCTFail("Expected mouse, Mos scroll, and Logi categories to exist in shortcut menu")
        }

        XCTAssertLessThan(mouseIndex, mosIndex)
        XCTAssertLessThan(mosIndex, logiIndex)
        XCTAssertNotNil(menu.items[mosIndex].image)

        let mosItems = menu.items[mosIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        }
        XCTAssertEqual(mosItems, ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"])
    }

    func testBuildShortcutMenu_includesOpenTargetEntryAboveCustom() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        guard let openIndex = menu.items.firstIndex(where: {
            ($0.representedObject as? String) == "__open__"
        }) else {
            return XCTFail("Expected '__open__' menu entry to exist")
        }
        guard let customIndex = menu.items.firstIndex(where: {
            ($0.representedObject as? String) == "__custom__"
        }) else {
            return XCTFail("Expected '__custom__' menu entry to exist")
        }
        XCTAssertLessThan(openIndex, customIndex, "Open Application should appear above Custom Shortcut")

        let openItem = menu.items[openIndex]
        XCTAssertEqual(openItem.title, NSLocalizedString("open-target-action", comment: ""))
    }

    func testBuildShortcutMenu_disablesMouseLeftClickAction() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)
        guard let mouseCategory = menu.items.first(where: { $0.title == mouseCategoryName }),
              let leftClickItem = mouseCategory.submenu?.items.first(where: {
                  ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == "mouseLeftClick"
              }) else {
            return XCTFail("Expected mouse left click item in mouse buttons category")
        }

        XCTAssertFalse(leftClickItem.isEnabled)
    }

    func testBuildShortcutMenu_keepsManualDisabledStateDuringMenuPresentation() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)
        guard let mouseCategory = menu.items.first(where: { $0.title == mouseCategoryName }),
              let mouseSubmenu = mouseCategory.submenu,
              let leftClickItem = mouseSubmenu.items.first(where: {
                  ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == "mouseLeftClick"
              }) else {
            return XCTFail("Expected mouse left click item in mouse buttons category")
        }

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertFalse(mouseSubmenu.autoenablesItems)
        mouseSubmenu.update()
        XCTAssertFalse(leftClickItem.isEnabled)
    }

    func testBuildShortcutMenu_usesShortCustomShortcutTitle() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        guard let customItem = menu.items.first(where: {
            ($0.representedObject as? String) == "__custom__"
        }) else {
            return XCTFail("Expected custom shortcut item")
        }

        XCTAssertFalse(customItem.title.contains("Key"))
        XCTAssertFalse(customItem.title.contains("按键"))
    }

    func testShortcutSelected_openSentinel_invokesOpenSelectionCallback() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "")

        var openSelectionInvoked = false
        let cell = makeButtonCell(binding: binding, onOpenTargetSelectionRequested: {
            openSelectionInvoked = true
        })

        let openItem = NSMenuItem(title: "Open Application…", action: nil, keyEquivalent: "")
        openItem.representedObject = "__open__" as NSString
        cell.shortcutSelected(openItem)

        XCTAssertTrue(openSelectionInvoked, "Selecting the __open__ menu item should trigger onOpenTargetSelectionRequested")
    }

    func testShortcutSelected_openSentinelRestoresCurrentActionDisplay() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy")
        let cell = makeButtonCell(binding: binding)
        cell.actionPopUpButton.menu?.items.first?.title = NSLocalizedString("open-target-action", comment: "")

        let openItem = NSMenuItem(title: "Open Application…", action: nil, keyEquivalent: "")
        openItem.representedObject = "__open__" as NSString
        cell.shortcutSelected(openItem)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.copy.localizedName)
    }

    func testBuildShortcutMenu_includesEscapeInFunctionKeysCategory() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let functionCategoryName = SystemShortcut.localizedCategoryName("categoryFunctionKeys")
        guard let functionCategoryIndex = menu.items.firstIndex(where: { $0.title == functionCategoryName }) else {
            return XCTFail("Expected function keys category to exist in shortcut menu")
        }

        let functionItems = menu.items[functionCategoryIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        } ?? []

        XCTAssertTrue(functionItems.contains("escapeKey"))
    }

    func testPredefinedModifierShortcut_localizedNamesAreSemanticLabels() {
        let symbolFallbacks = [
            "modifierShift": "⇧",
            "modifierOption": "⌥",
            "modifierControl": "⌃",
            "modifierCommand": "⌘",
            "modifierFn": "Fn",
        ]

        for (identifier, symbolFallback) in symbolFallbacks {
            guard let shortcut = SystemShortcut.getShortcut(named: identifier) else {
                return XCTFail("Expected shortcut \(identifier) to exist")
            }
            XCTAssertFalse(shortcut.localizedName.isEmpty)
            XCTAssertNotEqual(shortcut.localizedName, symbolFallback)
        }
    }

    func testEscapeShortcut_localizedNameIsSemanticLabel() {
        guard let shortcut = SystemShortcut.getShortcut(named: "escapeKey") else {
            return XCTFail("Expected escape shortcut to exist")
        }

        XCTAssertEqual(shortcut.localizedName, NSLocalizedString("escapeKey", comment: ""))
        XCTAssertNotEqual(shortcut.localizedName, "escapeKey")
    }

    func testConfiguredButtonCell_showsNamedShortcutForEquivalentCustomBinding() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::21:\(modifiers)"
        )

        let cell = makeButtonCell(binding: binding)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
        XCTAssertEqual(cell.actionPopUpButton.titleOfSelectedItem, SystemShortcut.screenshotSelection.localizedName)
    }

    func testConfiguredButtonCell_preservesDirectNamedShortcutForEquivalentConflictingCombo() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "getInfo"
        )

        let cell = makeButtonCell(binding: binding)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.getInfo.localizedName)
    }

    func testBeginCustomShortcutSelection_showsRecordingPromptWhileAwaitingRecording() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)

        cell.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()

        XCTAssertEqual(
            cell.actionPopUpButton.menu?.items.first?.title,
            NSLocalizedString("custom-recording-prompt", comment: "")
        )
    }

    func testCustomRecordingDidStop_restoresUnboundDisplayWhenNoKeyRecorded() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)

        cell.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        cell.onRecordingStopped(KeyRecorder(), didRecord: false)
        flushMainQueue()

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, NSLocalizedString("unbound", comment: ""))
    }

    func testCustomRecordingDidStop_restoresExistingDisplayWhenNoKeyRecorded() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::21:\(modifiers)"
        )
        let cell = makeButtonCell(binding: binding)

        cell.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        cell.onRecordingStopped(KeyRecorder(), didRecord: false)
        flushMainQueue()

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
    }

    func testRecordedEquivalentCustomShortcut_updatesSelectedActionDisplayToNamedShortcut() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)
        let event = InputEvent(
            type: .keyboard,
            code: 21,
            modifiers: [.maskCommand, .maskShift],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        cell.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        advanceMainRunLoop(by: 0.75)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
        XCTAssertEqual(cell.actionPopUpButton.titleOfSelectedItem, SystemShortcut.screenshotSelection.localizedName)
    }

    func testRecordedEquivalentCustomShortcut_withIrrelevantFlagsStillDisplaysNamedShortcut() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)
        let event = InputEvent(
            type: .keyboard,
            code: 21,
            modifiers: CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue) | (1 << 24)),
            phase: .down,
            source: .hidPP,
            device: nil
        )

        cell.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        advanceMainRunLoop(by: 0.75)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
        XCTAssertEqual(cell.actionPopUpButton.titleOfSelectedItem, SystemShortcut.screenshotSelection.localizedName)
    }

    func testRecordedMouseCustomShortcut_updatesSelectedActionDisplayToNamedMouseAction() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        cell.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        advanceMainRunLoop(by: 0.75)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, SystemShortcut.mouseBackClick.localizedName)
        XCTAssertEqual(cell.actionPopUpButton.titleOfSelectedItem, SystemShortcut.mouseBackClick.localizedName)
    }

    func testPrimaryMouseButtonsRecordabilityInAdaptiveMode() {
        let leftClick = InputEvent(
            type: .mouse,
            code: 0,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )
        let rightClick = InputEvent(
            type: .mouse,
            code: 1,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertFalse(leftClick.isRecordableAsAdaptive)
        XCTAssertFalse(leftClick.isRecordableAsSingleKey)
        XCTAssertFalse(leftClick.isRecordable)

        XCTAssertTrue(rightClick.isRecordableAsAdaptive)
        XCTAssertFalse(rightClick.isRecordableAsSingleKey)
        XCTAssertFalse(rightClick.isRecordable)
    }

    func testKeyPopoverDuplicateHintUsesDedicatedTextAndEscHintStyle() {
        let popover = KeyPopover()
        popover.testingPrepareContent()

        popover.showDuplicateHint()

        XCTAssertEqual(
            popover.testingHintText,
            NSLocalizedString("button-recording-duplicate-hint", comment: "")
        )
        XCTAssertEqual(popover.testingHintFontPointSize, 10)
        XCTAssertEqual(popover.testingHintAlignment, NSTextAlignment.center)
        XCTAssertEqual(popover.testingHintBottomPadding, 5)

        popover.hide()
    }

    func testKeyRecorderDuplicateFeedbackDelayIsLongerThanRecordedFeedback() {
        XCTAssertEqual(KeyRecorder.recordingFeedbackDelay(isDuplicate: false), 0.7)
        XCTAssertEqual(KeyRecorder.recordingFeedbackDelay(isDuplicate: true), 1.0)
    }

    func testCustomRecordingValidationRejectsRecordingTriggerItself() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertFalse(cell.validateRecordedEvent(KeyRecorder(), event: event))
    }

    func testDuplicateCustomRecordingRestoresPreviousActionDisplay() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        cell.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        cell.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: true)
        cell.onRecordingStopped(KeyRecorder(), didRecord: true)
        advanceMainRunLoop(by: KeyRecorder.recordingFeedbackDelay(isDuplicate: true) + 0.05)

        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, NSLocalizedString("unbound", comment: ""))
    }

    func testDuplicateCustomRecordingKeepsPromptUntilDuplicateFeedbackEnds() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let cell = makeButtonCell(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        cell.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        cell.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: true)

        advanceMainRunLoop(by: KeyRecorder.recordingFeedbackDelay(isDuplicate: false) + 0.05)
        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, NSLocalizedString("custom-recording-prompt", comment: ""))

        advanceMainRunLoop(by: KeyRecorder.recordingFeedbackDelay(isDuplicate: true))
        XCTAssertEqual(cell.actionPopUpButton.menu?.items.first?.title, NSLocalizedString("unbound", comment: ""))
    }

    // MARK: - OpenTarget extension

    func testOpenTargetSentinel_isStableConstant() {
        XCTAssertEqual(ButtonBinding.openTargetSentinel, "openTarget")
    }

    func testInit_withOpenTargetPayload_setsSentinelName() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "",
            kind: .application
        )
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
        XCTAssertEqual(binding.systemShortcutName, "openTarget")
        XCTAssertEqual(binding.openTarget, payload)
    }

    func testCodableRoundtrip_preservesOpenTarget() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "https://example.com",
            kind: .application
        )
        let original = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.systemShortcutName, "openTarget")
        XCTAssertEqual(decoded.openTarget, payload)
    }

    func testCodableRoundtrip_legacyBindingHasNilOpenTarget() {
        // Old JSON format: no openTarget field
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "triggerEvent": {
                "type": "mouse",
                "code": 3,
                "modifiers": 0,
                "displayComponents": ["🖱4"],
                "deviceFilter": null
            },
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try! decoder.decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.systemShortcutName, "copy")
        XCTAssertNil(decoded.openTarget)
    }

    func testEquatable_distinguishesByOpenTarget() {
        let payloadA = OpenTargetPayload(path: "/a.app", bundleID: nil, arguments: "", kind: .application)
        let payloadB = OpenTargetPayload(path: "/b.app", bundleID: nil, arguments: "", kind: .application)
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 0)

        let a = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadA, isEnabled: true, createdAt: createdAt)
        let b = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadA, isEnabled: true, createdAt: createdAt)
        let c = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadB, isEnabled: true, createdAt: createdAt)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Sentinel/payload consistency (decode 拒绝 mismatch)

    func testCodable_sentinelWithoutPayload_throws() {
        // {"systemShortcutName":"openTarget", 缺 openTarget} → 不一致, 应该 throw
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "openTarget",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(ButtonBinding.self, from: json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    func testCodable_payloadWithNonSentinelName_throws() {
        // {"systemShortcutName":"copy", "openTarget":{...}} → 不一致, 应该 throw
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z",
            "openTarget": {
                "path": "/Applications/Safari.app",
                "bundleID": "com.apple.Safari",
                "arguments": "",
                "kind": "application"
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(ButtonBinding.self, from: json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    func testCodable_sentinelWithPayload_decodesOK() {
        // 一致状态: 应正常 decode
        let json = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "openTarget",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z",
            "openTarget": {
                "path": "/Applications/Safari.app",
                "bundleID": "com.apple.Safari",
                "arguments": "https://example.com",
                "kind": "application"
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let binding = try! decoder.decode(ButtonBinding.self, from: json)
        XCTAssertEqual(binding.systemShortcutName, "openTarget")
        XCTAssertNotNil(binding.openTarget)
        XCTAssertEqual(binding.openTarget?.kind, .application)
    }

    func testCodable_nonSentinelWithoutPayload_decodesOK() {
        // 一致状态: 普通 system shortcut, 无 openTarget. 应正常 decode.
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let binding = try! decoder.decode(ButtonBinding.self, from: json)
        XCTAssertEqual(binding.systemShortcutName, "copy")
        XCTAssertNil(binding.openTarget)
    }
}
