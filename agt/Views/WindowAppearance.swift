import AppKit

/// Blends the window title bar with the terminal, mirroring macterm's `WindowAppearance`
/// (which in turn mirrors Ghostty's transparent-titlebar path). The trick that makes it
/// seamless: besides a transparent titlebar + `fullSizeContentView` + a window background
/// matching the terminal, AppKit's private `NSTitlebarView` paints its own material layer
/// that draws a visible band/seam at the titlebar height. Clearing that layer lets the
/// window background (and the full-size content below it) show through continuously.
@MainActor
enum WindowAppearance {
    /// Apply the blend to `window` using `background` (the terminal background color), at the given
    /// window `opacity` (0...1) and CGS `blurRadius`. Idempotent; safe to re-apply on attach and on
    /// every window/title/appearance update — AppKit rebuilds the titlebar subviews on key/main/
    /// fullscreen transitions, so re-applying is required to keep the seam gone.
    ///
    /// At full opacity the window is opaque with a solid background (the original behavior). Below
    /// full opacity the window goes non-opaque and its background carries the alpha: the renderer is
    /// pinned transparent (see `AppSettings.ghosttyConfigLines`) and the chrome paints nothing, so
    /// the whole interior reads as one continuous translucent surface, optionally blurred.
    static func sync(window: NSWindow, background: NSColor, opacity: Double, blurRadius: Int) {
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)

        // native fullscreen draws its own opaque background and the chrome shows through any
        // transparency, so force opaque while fullscreened.
        let transparent = opacity < 1 && !window.styleMask.contains(.fullScreen)
        if transparent {
            window.isOpaque = false
            window.backgroundColor = background.withAlphaComponent(opacity)
            setWindowBackgroundBlur(window, radius: blurRadius)
        } else {
            window.isOpaque = true
            window.backgroundColor = background
            setWindowBackgroundBlur(window, radius: 0) // clear any blur applied while translucent
        }

        // on macOS 26 the NavigationSplitView sidebar is a Liquid Glass container that wraps the
        // sidebar content, so it can't be flattened to the window tint like the terminal pane. Tint
        // that glass to the terminal color at the chosen opacity so the sidebar reads as the same
        // translucent surface; at full opacity the tint is cleared so the default glass returns.
        // its blur stays Liquid Glass, not the window-level CGS blur — close, not pixel-identical.
        if #available(macOS 26.0, *), let glass = sidebarGlass(in: window) {
            // `.clear` is the see-through glass variant — closer to the terminal's flat transparency
            // than the default frosty `.regular`; the tint supplies the terminal color.
            glass.style = transparent ? .clear : .regular
            glass.tintColor = transparent ? background.withAlphaComponent(opacity) : nil
        }

        // the title/terminal separator is drawn in the detail pane (ContentView), so it
        // ends at the sidebar edge rather than spanning the full titlebar width.
        guard let container = titlebarContainer(in: window) else { return }
        if let titlebarView = container.firstDescendant(withClassName: "NSTitlebarView") {
            titlebarView.wantsLayer = true
            titlebarView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        // NSTitlebarBackgroundView forces its own opaque material; hide it only when transparent so
        // the translucent window background shows through the titlebar continuously.
        container.firstDescendant(withClassName: "NSTitlebarBackgroundView")?.isHidden = transparent
    }

    /// The sidebar's Liquid Glass container, found by walking up from the tagged sidebar scroll view
    /// to its first `NSGlassEffectView` ancestor (the `NSContainerConcentricGlassEffectView` that
    /// `NavigationSplitView` wraps the sidebar in on macOS 26).
    @available(macOS 26.0, *)
    private static func sidebarGlass(in window: NSWindow) -> NSGlassEffectView? {
        guard let contentView = window.contentView else { return nil }
        var root: NSView = contentView
        while let parent = root.superview { root = parent }
        guard let scroll = root.firstDescendant(withIdentifier: "agt-sidebar-scroll") else { return nil }
        var node: NSView? = scroll.superview
        while let n = node {
            if let glass = n as? NSGlassEffectView { return glass }
            node = n.superview
        }
        return nil
    }

    /// The `NSTitlebarContainerView` for `window` — a descendant of the window's root
    /// theme frame (the superview chain above the content view).
    private static func titlebarContainer(in window: NSWindow) -> NSView? {
        guard let contentView = window.contentView else { return nil }
        var root: NSView = contentView
        while let parent = root.superview { root = parent }
        if String(describing: type(of: root)) == "NSTitlebarContainerView" { return root }
        return root.firstDescendant(withClassName: "NSTitlebarContainerView")
    }
}

// MARK: - Private CGS background-blur SPI

// `CGSSetWindowBackgroundBlurRadius` is the private CoreGraphics call every macOS terminal
// (Terminal.app, iTerm, Ghostty) uses to blur the content behind a translucent window. Undocumented
// but long-stable; libghostty calls the same symbol. Resolved once via dlsym; a missing symbol
// degrades to a no-op (no blur) rather than crashing. Adapted from thdxg/macterm (MIT).
private let cgsDefaultConnection: (@convention(c) () -> Int32)? = {
    guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGSDefaultConnectionForThread") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)
}()

private let cgsSetWindowBackgroundBlur: (@convention(c) (Int32, Int, Int32) -> Int32)? = {
    guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGSSetWindowBackgroundBlurRadius") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Int32, Int, Int32) -> Int32).self)
}()

@MainActor
private func setWindowBackgroundBlur(_ window: NSWindow, radius: Int) {
    guard let cgsDefaultConnection, let cgsSetWindowBackgroundBlur else { return }
    _ = cgsSetWindowBackgroundBlur(cgsDefaultConnection(), window.windowNumber, Int32(radius))
}

extension NSView {
    /// Depth-first search for the first descendant whose runtime class name matches.
    /// Used to reach AppKit's private titlebar views by class name.
    func firstDescendant(withClassName className: String) -> NSView? {
        for subview in subviews {
            if String(describing: type(of: subview)) == className { return subview }
            if let found = subview.firstDescendant(withClassName: className) { return found }
        }
        return nil
    }

    /// Depth-first search for the first descendant (or self) carrying the given identifier.
    /// Used to locate the tagged sidebar scroll view so its enclosing glass can be reached.
    func firstDescendant(withIdentifier identifier: String) -> NSView? {
        if self.identifier?.rawValue == identifier { return self }
        for subview in subviews {
            if let found = subview.firstDescendant(withIdentifier: identifier) { return found }
        }
        return nil
    }
}
