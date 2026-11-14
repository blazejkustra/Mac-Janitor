/// What a category's tile in the panel says.
public enum TileState: Equatable {
    case checking
    case found(Int64)
    case nothing
    /// The rule hit an issue and found nothing, which does not mean there is nothing.
    case unchecked

    public init(covered: Bool, bytes: Int64, hasIssue: Bool) {
        if !covered {
            self = .checking
        } else if bytes > 0 {
            self = .found(bytes)
        } else {
            self = hasIssue ? .unchecked : .nothing
        }
    }
}
