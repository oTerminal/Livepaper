import LivepaperCore

extension AppModel {
    /// A fakes model for the screens' `#Preview`s: the library seeded or empty,
    /// on the two fake displays, with the host's status as given. Its actions
    /// work, on the fake host; nothing is sensed.
    ///
    ///     #Preview { PopoverView().environment(AppModel.preview()) }
    static func preview(_ library: FakeLibrary = .seeded, hostStatus: RenderHostStatus = .live) -> AppModel {
        let fakes = Fakes(library: library)
        let model = AppModel(services: fakes.makeServices())
        model.prepareForPreview(displays: fakes.connectedDisplays, hostStatus: hostStatus)
        return model
    }
}
