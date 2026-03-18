import Foundation
import Yams

public struct GitHubWorkflowPushTrigger: Hashable, Sendable {
    public let branches: [String]
    public let branchesIgnore: [String]
    public let tags: [String]
    public let tagsIgnore: [String]
    public let paths: [String]
    public let pathsIgnore: [String]

    public static let `default` = GitHubWorkflowPushTrigger(
        branches: [],
        branchesIgnore: [],
        tags: [],
        tagsIgnore: [],
        paths: [],
        pathsIgnore: []
    )

    public init(
        branches: [String],
        branchesIgnore: [String],
        tags: [String],
        tagsIgnore: [String],
        paths: [String],
        pathsIgnore: [String]
    ) {
        self.branches = branches
        self.branchesIgnore = branchesIgnore
        self.tags = tags
        self.tagsIgnore = tagsIgnore
        self.paths = paths
        self.pathsIgnore = pathsIgnore
    }
}

public struct GitHubWorkflowFileDefinition: Hashable, Sendable {
    public let name: String?
    public let pushTrigger: GitHubWorkflowPushTrigger?

    public init(name: String?, pushTrigger: GitHubWorkflowPushTrigger?) {
        self.name = name
        self.pushTrigger = pushTrigger
    }
}

public struct GitHubWorkflowFileDiagnosticLocation: Hashable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public enum GitHubWorkflowFileDiagnosticKind: String, Hashable, Sendable {
    case emptyDocument
    case invalidYAML
    case unsupportedRootNode
    case unsupportedOnConfiguration
    case unsupportedPushConfiguration
    case unsupportedFilterValue
}

public struct GitHubWorkflowFileDiagnostic: Hashable, Sendable {
    public let kind: GitHubWorkflowFileDiagnosticKind
    public let message: String
    public let location: GitHubWorkflowFileDiagnosticLocation?

    public init(
        kind: GitHubWorkflowFileDiagnosticKind,
        message: String,
        location: GitHubWorkflowFileDiagnosticLocation? = nil
    ) {
        self.kind = kind
        self.message = message
        self.location = location
    }
}

public struct GitHubWorkflowFileParseResult: Hashable, Sendable {
    public let definition: GitHubWorkflowFileDefinition?
    public let diagnostics: [GitHubWorkflowFileDiagnostic]

    public init(
        definition: GitHubWorkflowFileDefinition?,
        diagnostics: [GitHubWorkflowFileDiagnostic]
    ) {
        self.definition = definition
        self.diagnostics = diagnostics
    }
}

public enum GitHubWorkflowFileParser {
    public static func parse(_ content: String) -> GitHubWorkflowFileParseResult {
        do {
            guard let document = try Yams.load(yaml: content, .basic) else {
                return GitHubWorkflowFileParseResult(
                    definition: nil,
                    diagnostics: [
                        GitHubWorkflowFileDiagnostic(
                            kind: .emptyDocument,
                            message: "The workflow file is empty."
                        )
                    ]
                )
            }

            return parseDocument(document)
        } catch let error as YamlError {
            return GitHubWorkflowFileParseResult(
                definition: nil,
                diagnostics: [diagnostic(from: error)]
            )
        } catch {
            return GitHubWorkflowFileParseResult(
                definition: nil,
                diagnostics: [
                    GitHubWorkflowFileDiagnostic(
                        kind: .invalidYAML,
                        message: "Octowatch could not parse this YAML document."
                    )
                ]
            )
        }
    }

    private static func parseDocument(_ document: Any) -> GitHubWorkflowFileParseResult {
        guard let root = stringKeyedMapping(from: document) else {
            return GitHubWorkflowFileParseResult(
                definition: nil,
                diagnostics: [
                    GitHubWorkflowFileDiagnostic(
                        kind: .unsupportedRootNode,
                        message: "The workflow file must use a top-level mapping."
                    )
                ]
            )
        }

        let workflowName = scalarString(from: value(for: "name", in: root))

        guard let onValue = value(for: "on", in: root) else {
            return GitHubWorkflowFileParseResult(
                definition: GitHubWorkflowFileDefinition(
                    name: workflowName,
                    pushTrigger: nil
                ),
                diagnostics: []
            )
        }

        switch parseOnValue(onValue) {
        case .noPush:
            return GitHubWorkflowFileParseResult(
                definition: GitHubWorkflowFileDefinition(
                    name: workflowName,
                    pushTrigger: nil
                ),
                diagnostics: []
            )
        case let .trigger(pushTrigger):
            return GitHubWorkflowFileParseResult(
                definition: GitHubWorkflowFileDefinition(
                    name: workflowName,
                    pushTrigger: pushTrigger
                ),
                diagnostics: []
            )
        case let .unsupported(diagnostic):
            return GitHubWorkflowFileParseResult(
                definition: GitHubWorkflowFileDefinition(
                    name: workflowName,
                    pushTrigger: nil
                ),
                diagnostics: [diagnostic]
            )
        }
    }

    private static func parseOnValue(_ rawValue: Any) -> PushTriggerParseOutcome {
        if let event = scalarString(from: rawValue) {
            return normalizedScalar(event) == "push" ? .trigger(.default) : .noPush
        }

        if let events = sequence(from: rawValue) {
            let eventNames = events.compactMap { scalarString(from: $0) }.map(normalizedScalar)
            guard eventNames.count == events.count else {
                return .unsupported(
                    GitHubWorkflowFileDiagnostic(
                        kind: .unsupportedOnConfiguration,
                        message: "Octowatch cannot evaluate this `on:` declaration because it is not a string or list of event names."
                    )
                )
            }

            return eventNames.contains("push") ? .trigger(.default) : .noPush
        }

        guard let onMapping = stringKeyedMapping(from: rawValue) else {
            return .unsupported(
                GitHubWorkflowFileDiagnostic(
                    kind: .unsupportedOnConfiguration,
                    message: "Octowatch cannot evaluate this `on:` declaration."
                )
            )
        }

        guard let pushValue = value(for: "push", in: onMapping) else {
            return .noPush
        }

        if isNull(pushValue) {
            return .trigger(.default)
        }

        guard let pushMapping = stringKeyedMapping(from: pushValue) else {
            return .unsupported(
                GitHubWorkflowFileDiagnostic(
                    kind: .unsupportedPushConfiguration,
                    message: "Octowatch cannot evaluate this `push` configuration."
                )
            )
        }

        return parsePushMapping(pushMapping)
    }

    private static func parsePushMapping(_ mapping: [String: Any]) -> PushTriggerParseOutcome {
        var branches = [String]()
        var branchesIgnore = [String]()
        var tags = [String]()
        var tagsIgnore = [String]()
        var paths = [String]()
        var pathsIgnore = [String]()

        for (rawKey, rawValue) in mapping {
            switch normalizedScalar(rawKey) {
            case "branches":
                guard let values = stringPatterns(from: rawValue, filterName: "branches") else {
                    return .unsupported(
                        invalidFilterDiagnostic(filterName: "branches")
                    )
                }
                branches = values
            case "branches-ignore":
                guard let values = stringPatterns(from: rawValue, filterName: "branches-ignore") else {
                    return .unsupported(
                        invalidFilterDiagnostic(filterName: "branches-ignore")
                    )
                }
                branchesIgnore = values
            case "tags":
                guard let values = stringPatterns(from: rawValue, filterName: "tags") else {
                    return .unsupported(
                        invalidFilterDiagnostic(filterName: "tags")
                    )
                }
                tags = values
            case "tags-ignore":
                guard let values = stringPatterns(from: rawValue, filterName: "tags-ignore") else {
                    return .unsupported(
                        invalidFilterDiagnostic(filterName: "tags-ignore")
                    )
                }
                tagsIgnore = values
            case "paths":
                guard let values = stringPatterns(from: rawValue, filterName: "paths") else {
                    return .unsupported(
                        invalidFilterDiagnostic(filterName: "paths")
                    )
                }
                paths = values
            case "paths-ignore":
                guard let values = stringPatterns(from: rawValue, filterName: "paths-ignore") else {
                    return .unsupported(
                        invalidFilterDiagnostic(filterName: "paths-ignore")
                    )
                }
                pathsIgnore = values
            default:
                continue
            }
        }

        return .trigger(
            GitHubWorkflowPushTrigger(
                branches: branches,
                branchesIgnore: branchesIgnore,
                tags: tags,
                tagsIgnore: tagsIgnore,
                paths: paths,
                pathsIgnore: pathsIgnore
            )
        )
    }

    private static func stringKeyedMapping(from rawValue: Any) -> [String: Any]? {
        if let mapping = rawValue as? [String: Any] {
            return mapping
        }

        guard let mapping = rawValue as? [AnyHashable: Any] else {
            return nil
        }

        var result = [String: Any]()
        result.reserveCapacity(mapping.count)

        for (key, value) in mapping {
            guard let stringKey = key as? String else {
                return nil
            }

            result[stringKey] = value
        }

        return result
    }

    private static func sequence(from rawValue: Any) -> [Any]? {
        rawValue as? [Any]
    }

    private static func scalarString(from rawValue: Any?) -> String? {
        guard let rawValue else {
            return nil
        }

        return rawValue as? String
    }

    private static func stringPatterns(from rawValue: Any, filterName: String) -> [String]? {
        if let value = scalarString(from: rawValue) {
            let normalized = normalizedScalar(value)
            return normalized.isEmpty ? nil : [normalized]
        }

        guard let values = sequence(from: rawValue) else {
            return nil
        }

        let patterns = values.compactMap { scalarString(from: $0) }.map(normalizedScalar)
        guard patterns.count == values.count, !patterns.contains(where: \.isEmpty) else {
            return nil
        }

        return patterns
    }

    private static func value(
        for key: String,
        in mapping: [String: Any]
    ) -> Any? {
        mapping.first { normalizedScalar($0.key) == key }?.value
    }

    private static func normalizedScalar(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNull(_ rawValue: Any) -> Bool {
        rawValue is NSNull
    }

    private static func invalidFilterDiagnostic(
        filterName: String
    ) -> GitHubWorkflowFileDiagnostic {
        GitHubWorkflowFileDiagnostic(
            kind: .unsupportedFilterValue,
            message: "The `\(filterName)` filter must be a string or list of strings."
        )
    }

    private static func diagnostic(from error: YamlError) -> GitHubWorkflowFileDiagnostic {
        switch error {
        case let .reader(problem, _, _, _):
            return GitHubWorkflowFileDiagnostic(
                kind: .invalidYAML,
                message: "YAML could not be read: \(problem)"
            )
        case let .scanner(context, problem, mark, _):
            return GitHubWorkflowFileDiagnostic(
                kind: .invalidYAML,
                message: yamlMessage(problem: problem, context: context?.text),
                location: GitHubWorkflowFileDiagnosticLocation(
                    line: mark.line,
                    column: mark.column
                )
            )
        case let .parser(context, problem, mark, _):
            return GitHubWorkflowFileDiagnostic(
                kind: .invalidYAML,
                message: yamlMessage(problem: problem, context: context?.text),
                location: GitHubWorkflowFileDiagnosticLocation(
                    line: mark.line,
                    column: mark.column
                )
            )
        case let .composer(context, problem, mark, _):
            return GitHubWorkflowFileDiagnostic(
                kind: .invalidYAML,
                message: yamlMessage(problem: problem, context: context?.text),
                location: GitHubWorkflowFileDiagnosticLocation(
                    line: mark.line,
                    column: mark.column
                )
            )
        case let .duplicatedKeysInMapping(_, context):
            return GitHubWorkflowFileDiagnostic(
                kind: .invalidYAML,
                message: "The workflow file defines the same mapping key more than once.",
                location: GitHubWorkflowFileDiagnosticLocation(
                    line: context.mark.line,
                    column: context.mark.column
                )
            )
        case .writer, .emitter, .representer, .memory, .no, .dataCouldNotBeDecoded:
            return GitHubWorkflowFileDiagnostic(
                kind: .invalidYAML,
                message: "Octowatch could not parse this YAML document."
            )
        }
    }

    private static func yamlMessage(
        problem: String,
        context: String?
    ) -> String {
        guard let context, !context.isEmpty else {
            return problem
        }

        return "\(context): \(problem)"
    }

    private enum PushTriggerParseOutcome {
        case noPush
        case trigger(GitHubWorkflowPushTrigger)
        case unsupported(GitHubWorkflowFileDiagnostic)
    }
}

public enum GitHubWorkflowPathFilterPolicy {
    public static func matches(
        trigger: GitHubWorkflowPushTrigger,
        branch: String,
        changedFiles: [String]
    ) -> Bool {
        let hasBranchFilters = !trigger.branches.isEmpty || !trigger.branchesIgnore.isEmpty
        let hasTagFilters = !trigger.tags.isEmpty || !trigger.tagsIgnore.isEmpty

        if hasTagFilters && !hasBranchFilters {
            return false
        }

        if !trigger.branches.isEmpty &&
            !matchesOrderedPatterns(trigger.branches, value: branch) {
            return false
        }

        if trigger.branchesIgnore.contains(where: { matchesPattern($0, value: branch) }) {
            return false
        }

        if !trigger.paths.isEmpty {
            guard changedFiles.contains(where: { matchesOrderedPatterns(trigger.paths, value: $0) }) else {
                return false
            }
        }

        if !trigger.pathsIgnore.isEmpty {
            let allIgnored = changedFiles.allSatisfy { path in
                trigger.pathsIgnore.contains(where: { matchesPattern($0, value: path) })
            }
            if allIgnored {
                return false
            }
        }

        return true
    }

    private static func matchesOrderedPatterns(
        _ patterns: [String],
        value: String
    ) -> Bool {
        var isIncluded = false
        var sawPositive = false

        for pattern in patterns {
            let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPattern.isEmpty else {
                continue
            }

            if normalizedPattern.hasPrefix("!") {
                let candidate = String(normalizedPattern.dropFirst())
                if matchesPattern(candidate, value: value) {
                    isIncluded = false
                }
                continue
            }

            sawPositive = true
            if matchesPattern(normalizedPattern, value: value) {
                isIncluded = true
            }
        }

        return sawPositive ? isIncluded : false
    }

    private static func matchesPattern(
        _ pattern: String,
        value: String
    ) -> Bool {
        let regexPattern = regex(for: pattern)
        return value.range(of: regexPattern, options: .regularExpression) != nil
    }

    private static func regex(for pattern: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let placeholder = "__DOUBLE_STAR__"
        let withDoubleStars = escaped.replacingOccurrences(of: "\\*\\*", with: placeholder)
        let withSingleStars = withDoubleStars.replacingOccurrences(of: "\\*", with: "[^/]*")
        let withQuestionMarks = withSingleStars.replacingOccurrences(of: "\\?", with: "[^/]")
        let restored = withQuestionMarks.replacingOccurrences(of: placeholder, with: ".*")
        return "^\(restored)$"
    }
}
