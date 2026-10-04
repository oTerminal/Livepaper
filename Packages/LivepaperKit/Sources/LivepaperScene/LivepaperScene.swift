/// Wallpaper Engine scenes.
///
/// What the product knows of a scene's files, and how it draws one. Reading:
/// `ScenePackage` (a `.pkg`), `SceneTexture` and `SpriteSheet` (a `.tex`),
/// `ScenePuppet` (a `.mdl`), `SceneDocument` (the scene's JSON, its user
/// properties at the item's defaults) and `readSceneOutline` (what an import
/// needs, the GIF-scene rule among it). Drawing: the `SceneDrawing` seam and
/// `WallpaperEngineScene` behind it, from the programs the import translated
/// (`ScenePrograms`; the translation is `LivepaperImport`'s, since the
/// extension never runs it), our stand-ins for Wallpaper Engine's own
/// textures (`ParticleTextures`), and the scene's sounds (`SceneSoundtrack`).
public enum LivepaperScene {
    /// The rate a scene is drawn at. Heavy scenes could not hold 60 on the
    /// spike's Mac while light ones held either.
    public static let framesPerSecond = 30.0
}
