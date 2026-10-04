/// Turns files the user provides into library wallpapers.
///
/// `discoverSources` finds the source files, and `Importer` takes each through
/// the stages: fingerprint, probe, plan, convert (the ffmpeg helper, for the
/// files AVFoundation cannot open), normalise (writing the optimised copy),
/// validate the loop seam, artefacts, commit. `sweepInterruptedImports` is for
/// launch, after an import that was killed.
public enum LivepaperImport {}
