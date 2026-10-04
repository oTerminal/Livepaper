import CoreGraphics

/// How far an element follows a drag that has gone `offset` past an edge:
/// progressively less, and never as far as `limit`. A hard stop reads as frozen;
/// resistance reads as "nothing more here".
public nonisolated func rubberband(offset: CGFloat, limit: CGFloat) -> CGFloat {
    let constant = rubberbandConstant
    guard limit > 0 else { return 0 }
    return (offset * limit * constant) / (limit + constant * abs(offset))
}

/// The drag past the edge that `rubberband` turned into `offset`. Picking an
/// element up while it is still past its edge continues from here, so it does
/// not jump. An offset at or beyond `limit` has no finite drag behind it.
public nonisolated func unrubberband(offset: CGFloat, limit: CGFloat) -> CGFloat {
    let constant = rubberbandConstant
    guard limit > 0, offset != 0 else { return 0 }
    guard abs(offset) < limit else { return offset > 0 ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude }
    return (offset * limit) / (constant * (limit - abs(offset)))
}

/// Apple's constant, from the Designing Fluid Interfaces sample code.
private nonisolated let rubberbandConstant: CGFloat = 0.55
