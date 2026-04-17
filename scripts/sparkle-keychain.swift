#!/usr/bin/env swift

import CryptoKit
import Foundation
import Security

let sparkleService = "https://sparkle-project.org"
let sparkleLabel = "Private key for signing Sparkle updates"

enum Command: String {
    case exportSecret = "export-secret"
    case printPublicKey = "print-public-key"
    case importBundle = "import-bundle"
    case sync
    case help
}

enum StoreKind: String {
    case local
    case synchronizable
}

enum SourcePreference: String {
    case local
    case synchronizable
    case preferLocal = "prefer-local"
    case preferSynchronizable = "prefer-synchronizable"
}

struct Options {
    var command: Command = .help
    var account = "ed25519"
    var bundleID: String?
    var source: SourcePreference?
    var from: StoreKind = .local
    var to: StoreKind = .synchronizable
    var sourceAccount = "ed25519"
}

enum ScriptError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}

func printUsage() {
    print(
        """
        Usage:
          scripts/sparkle-keychain.swift export-secret [--account <name> | --bundle-id <bundle-id>] [--source <local|synchronizable|prefer-local|prefer-synchronizable>]
          scripts/sparkle-keychain.swift print-public-key [--account <name> | --bundle-id <bundle-id>] [--source <local|synchronizable|prefer-local|prefer-synchronizable>]
          scripts/sparkle-keychain.swift import-bundle --bundle-id <bundle-id> [--source-account <name>] [--source <local|synchronizable|prefer-local|prefer-synchronizable>]
          scripts/sparkle-keychain.swift sync [--account <name>] [--from <local|synchronizable>] [--to <local|synchronizable>]

        Notes:
          - Sparkle's stock tools only query the non-synchronizable item.
          - `import-bundle` stores a synchronizable copy as account `sparkle: <bundle-id>`.
          - This helper can read and write a synchronizable copy for iCloud Keychain sync.
          - `sync` copies the secret between stores without changing the key material.
        """
    )
}

func parseOptions(arguments: [String]) throws -> Options {
    var options = Options()

    guard arguments.count >= 2 else {
        return options
    }

    if arguments[1] == "--help" || arguments[1] == "-h" {
        return options
    }

    guard let command = Command(rawValue: arguments[1]) else {
        throw ScriptError.message("unknown command: \(arguments[1])")
    }
    options.command = command

    var index = 2
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--account":
            index += 1
            guard index < arguments.count else {
                throw ScriptError.message("--account requires a value")
            }
            options.account = arguments[index]
        case "--bundle-id":
            index += 1
            guard index < arguments.count else {
                throw ScriptError.message("--bundle-id requires a value")
            }
            options.bundleID = arguments[index]
        case "--source":
            index += 1
            guard index < arguments.count else {
                throw ScriptError.message("--source requires a value")
            }
            guard let source = SourcePreference(rawValue: arguments[index]) else {
                throw ScriptError.message("invalid --source value: \(arguments[index])")
            }
            options.source = source
        case "--source-account":
            index += 1
            guard index < arguments.count else {
                throw ScriptError.message("--source-account requires a value")
            }
            options.sourceAccount = arguments[index]
        case "--from":
            index += 1
            guard index < arguments.count else {
                throw ScriptError.message("--from requires a value")
            }
            guard let from = StoreKind(rawValue: arguments[index]) else {
                throw ScriptError.message("invalid --from value: \(arguments[index])")
            }
            options.from = from
        case "--to":
            index += 1
            guard index < arguments.count else {
                throw ScriptError.message("--to requires a value")
            }
            guard let to = StoreKind(rawValue: arguments[index]) else {
                throw ScriptError.message("invalid --to value: \(arguments[index])")
            }
            options.to = to
        case "--help", "-h":
            options.command = .help
        default:
            throw ScriptError.message("unknown argument: \(argument)")
        }
        index += 1
    }

    return options
}

func bundleAccount(bundleID: String) -> String {
    "sparkle: \(bundleID)"
}

func keychainQuery(account: String, kind: StoreKind) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: sparkleService,
        kSecAttrAccount as String: account,
        kSecAttrProtocol as String: kSecAttrProtocolSSH
    ]

    if kind == .synchronizable {
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
    }

    return query
}

func decodePublicKey(secret: Data) throws -> Data {
    if secret.count == 32 {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
        return key.publicKey.rawRepresentation
    }

    if secret.count == 96 {
        return secret.suffix(32)
    }

    throw ScriptError.message("unsupported Sparkle secret length: \(secret.count) bytes")
}

func loadSecret(account: String, kind: StoreKind) throws -> Data? {
    var item: CFTypeRef?
    var query = keychainQuery(account: account, kind: kind)
    query[kSecReturnData as String] = kCFBooleanTrue

    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
        guard
            let encoded = item as? Data,
            let secret = Data(base64Encoded: encoded)
        else {
            throw ScriptError.message("failed to decode Sparkle secret from the \(kind.rawValue) keychain item")
        }
        return secret
    case errSecItemNotFound:
        return nil
    default:
        throw ScriptError.message("keychain lookup failed for \(kind.rawValue) item: \(status)")
    }
}

func preferredStoreOrder(_ preference: SourcePreference) -> [StoreKind] {
    switch preference {
    case .local:
        return [.local]
    case .synchronizable:
        return [.synchronizable]
    case .preferLocal:
        return [.local, .synchronizable]
    case .preferSynchronizable:
        return [.synchronizable, .local]
    }
}

func resolveSecret(account: String, source: SourcePreference) throws -> (secret: Data, kind: StoreKind) {
    for kind in preferredStoreOrder(source) {
        if let secret = try loadSecret(account: account, kind: kind) {
            return (secret, kind)
        }
    }

    throw ScriptError.message("no Sparkle key found for account '\(account)' in the requested keychain source(s)")
}

func storeSecret(account: String, secret: Data, kind: StoreKind, label: String = sparkleLabel) throws {
    let publicKey = try decodePublicKey(secret: secret)
    let encodedSecret = secret.base64EncodedData()

    let updateAttributes: [String: Any] = [
        kSecAttrIsSensitive as String: kCFBooleanTrue!,
        kSecAttrIsPermanent as String: kCFBooleanTrue!,
        kSecAttrLabel as String: label,
        kSecAttrComment as String: "Public key (SUPublicEDKey value) for this key is:\n\n\(publicKey.base64EncodedString())",
        kSecAttrDescription as String: "private key",
        kSecValueData as String: encodedSecret as CFData
    ]

    let addQuery = keychainQuery(account: account, kind: kind).merging(updateAttributes) { _, new in new }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    switch addStatus {
    case errSecSuccess:
        return
    case errSecDuplicateItem:
        let updateStatus = SecItemUpdate(
            keychainQuery(account: account, kind: kind) as CFDictionary,
            updateAttributes as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw ScriptError.message("failed to update \(kind.rawValue) keychain item: \(updateStatus)")
        }
    default:
        throw ScriptError.message("failed to store \(kind.rawValue) keychain item: \(addStatus)")
    }
}

func defaultSourcePreference(for command: Command) -> SourcePreference {
    switch command {
    case .importBundle:
        return .local
    case .exportSecret, .printPublicKey:
        return .preferSynchronizable
    case .sync, .help:
        return .preferSynchronizable
    }
}

func resolvedAccount(from options: Options) -> String {
    if let bundleID = options.bundleID {
        return bundleAccount(bundleID: bundleID)
    }

    return options.account
}

do {
    let options = try parseOptions(arguments: CommandLine.arguments)
    let sourcePreference = options.source ?? defaultSourcePreference(for: options.command)

    switch options.command {
    case .help:
        printUsage()
    case .exportSecret:
        let (secret, _) = try resolveSecret(account: resolvedAccount(from: options), source: sourcePreference)
        print(secret.base64EncodedString())
    case .printPublicKey:
        let (secret, _) = try resolveSecret(account: resolvedAccount(from: options), source: sourcePreference)
        print(try decodePublicKey(secret: secret).base64EncodedString())
    case .importBundle:
        guard let bundleID = options.bundleID else {
            throw ScriptError.message("--bundle-id is required for import-bundle")
        }

        let (secret, sourceKind) = try resolveSecret(account: options.sourceAccount, source: sourcePreference)
        let targetAccount = bundleAccount(bundleID: bundleID)
        try storeSecret(
            account: targetAccount,
            secret: secret,
            kind: .synchronizable,
            label: targetAccount
        )
        print("Imported Sparkle key for bundle '\(bundleID)' from \(sourceKind.rawValue) account '\(options.sourceAccount)' into synchronizable account '\(targetAccount)'.")
    case .sync:
        if options.from == options.to {
            throw ScriptError.message("--from and --to must be different")
        }

        guard let secret = try loadSecret(account: options.account, kind: options.from) else {
            throw ScriptError.message("no Sparkle key found in the \(options.from.rawValue) store for account '\(options.account)'")
        }

        try storeSecret(account: options.account, secret: secret, kind: options.to)
        print("Synced Sparkle key for account '\(options.account)' from \(options.from.rawValue) to \(options.to.rawValue).")
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
