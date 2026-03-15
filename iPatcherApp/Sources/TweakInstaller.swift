import Foundation

/// Manages installing/uninstalling the iPatcher tweak dylib via a setuid root helper.
///
/// The helper binary (`ipatcher-helper`) is shipped in the app bundle under TweakPayload/
/// and must be installed once as setuid root at the expected path. This is handled by
/// either the dpkg postinst script or a one-time SSH setup command.
class TweakInstaller: ObservableObject {
    static let shared = TweakInstaller()

    @Published var isInstalled = false
    @Published var needsRespring = false
    @Published var helperInstalled = false
    @Published var helperIssue: String?
    @Published var lastError: String?

    private let helperPath    = "/var/jb/usr/local/libexec/ipatcher-helper"
    private let substratePath = "/var/jb/Library/MobileSubstrate/DynamicLibraries"
    private let dylibName     = "iPatcher.dylib"
    private let filterName    = "iPatcher.plist"
    private let fm            = FileManager.default
    private let logger        = AppLogger.shared

    private var destDylib: String { (substratePath as NSString).appendingPathComponent(dylibName) }

    init() { checkStatus() }

    // MARK: - Status

    func checkStatus() {
        isInstalled = fm.fileExists(atPath: destDylib)
        helperIssue = helperValidationIssue()
        helperInstalled = (helperIssue == nil)
        logger.log("Status checked: isInstalled=\(isInstalled) helperInstalled=\(helperInstalled)")
    }

    // MARK: - Install helper (first-run: copies from bundle, user must chmod via SSH)

    func installHelperFromBundle() -> Bool {
        lastError = nil
        guard let src = embeddedPath(for: "ipatcher-helper") else {
            lastError = "Helper binary not found in app bundle."
            logger.log(lastError ?? "Helper binary not found in app bundle.", level: "ERROR")
            return false
        }

        // Try to copy — will work if destination dir is writable
        let destDir = (helperPath as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        } catch {}

        do {
            try? fm.removeItem(atPath: helperPath)
            try fm.copyItem(atPath: src, toPath: helperPath)
        } catch {
            lastError = "Copy helper failed: \(error.localizedDescription)\n\nRun via SSH:\n  cp '\(src)' '\(helperPath)'\n  chown root:wheel '\(helperPath)'\n  chmod 4755 '\(helperPath)'"
            logger.log("Copy helper failed: \(error.localizedDescription)", level: "ERROR")
            return false
        }

        // We copied it, but it still needs setuid — which requires root
        lastError = "Helper copied. Run via SSH as root:\n  chown root:wheel '\(helperPath)'\n  chmod 4755 '\(helperPath)'"
        logger.log("Helper copied to \(helperPath) but still needs root ownership/setuid")
        return false
    }

    // MARK: - Install Tweak

    func install() -> Bool {
        lastError = nil
        logger.log("Install requested")

        guard helperInstalled else {
            lastError = "Root helper not ready.\n\(helperIssue ?? "")\n\nRun once via SSH as root:\n  \(setupCommand())"
            logger.log(lastError ?? "Root helper not ready.", level: "ERROR")
            return false
        }

        guard let dylibSrc = embeddedPath(for: dylibName),
              let plistSrc = embeddedPath(for: filterName)
        else {
            lastError = "Embedded tweak payload not found in app bundle."
            logger.log(lastError ?? "Embedded tweak payload missing.", level: "ERROR")
            return false
        }

        let (ok, output) = runHelper("install", dylibSrc, plistSrc, substratePath)
        if ok {
            checkStatus()
            needsRespring = true
            logger.log("Install succeeded: \(output)")
            return true
        } else {
            lastError = "Install failed: \(output)"
            logger.log(lastError ?? "Install failed.", level: "ERROR")
            return false
        }
    }

    // MARK: - Uninstall

    func uninstall() -> Bool {
        lastError = nil
        logger.log("Uninstall requested")

        guard helperInstalled else {
            lastError = "Root helper not ready.\n\(helperIssue ?? "")"
            logger.log(lastError ?? "Root helper not ready.", level: "ERROR")
            return false
        }

        let (ok, output) = runHelper("uninstall", substratePath)
        if ok {
            checkStatus()
            needsRespring = true
            logger.log("Uninstall succeeded: \(output)")
            return true
        } else {
            lastError = "Uninstall failed: \(output)"
            logger.log(lastError ?? "Uninstall failed.", level: "ERROR")
            return false
        }
    }

    // MARK: - Update

    func update() -> Bool {
        _ = uninstall()
        return install()
    }

    // MARK: - Respring

    func respring() -> Bool {
        lastError = nil
        logger.log("Respring requested")

        if helperInstalled {
            let (ok, output) = runHelper("respring")
            if !ok {
                lastError = "Respring failed: \(output)"
                logger.log(lastError ?? "Respring failed.", level: "ERROR")
            } else {
                logger.log("Respring helper succeeded: \(output)")
            }
            return ok
        } else {
            // Fallback: try kill from our process (works with platform-application)
            let ok = killSpringBoard()
            if !ok {
                lastError = "Respring failed: could not signal SpringBoard"
                logger.log(lastError ?? "Respring fallback failed.", level: "ERROR")
            } else {
                logger.log("Respring fallback signaled SpringBoard")
            }
            return ok
        }
    }

    // MARK: - Setup command for display

    func setupCommand() -> String {
        if let src = embeddedPath(for: "ipatcher-helper") {
            return "cp '\(src)' '\(helperPath)' && chown root:wheel '\(helperPath)' && chmod 4755 '\(helperPath)'"
        }
        return "# Copy scripts/setup_helper.sh to the device and run it as root"
    }

    // MARK: - Private: run helper via posix_spawn

    @discardableResult
    private func runHelper(_ args: String...) -> (Bool, String) {
        let allArgs = [helperPath] + args
        let cArgs = allArgs.map { strdup($0) } + [nil]
        defer { cArgs.forEach { if let p = $0 { free(p) } } }

        let pipe = Pipe()
        let errPipe = Pipe()

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        var pid: pid_t = 0
        let ret = posix_spawn(&pid, helperPath, &fileActions, nil, cArgs, nil)
        posix_spawn_file_actions_destroy(&fileActions)

        if ret != 0 {
            logger.log("Helper spawn failed with code \(ret)", level: "ERROR")
            return (false, "spawn failed: \(ret)")
        }

        pipe.fileHandleForWriting.closeFile()
        errPipe.fileHandleForWriting.closeFile()

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        let stdout = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let output = (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        let exited = (status & 0x7f) == 0
        let exitCode = (status >> 8) & 0xff
        logger.log("Helper command \(args.joined(separator: " ")) exited=\(exited) code=\(exitCode) output=\(output)")
        return (exited && exitCode == 0, output)
    }

    // MARK: - Fallback respring (in-process kill)

    private func killSpringBoard() -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0)

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0)

        let actual = size / MemoryLayout<kinfo_proc>.stride
        for i in 0..<actual {
            let name = withUnsafePointer(to: procs[i].kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }
            if name == "SpringBoard" {
                return kill(procs[i].kp_proc.p_pid, SIGTERM) == 0
            }
        }

        return false
    }

    // MARK: - Helpers

    private func embeddedPath(for filename: String) -> String? {
        if let dir = Bundle.main.path(forResource: "TweakPayload", ofType: nil) {
            let path = (dir as NSString).appendingPathComponent(filename)
            if fm.fileExists(atPath: path) { return path }
        }
        let ext  = (filename as NSString).pathExtension
        let name = (filename as NSString).deletingPathExtension
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    private func helperValidationIssue() -> String? {
        guard fm.fileExists(atPath: helperPath) else {
            return "Missing at \(helperPath)"
        }
        guard fm.isExecutableFile(atPath: helperPath) else {
            return "Not executable at \(helperPath)"
        }

        guard let attrs = try? fm.attributesOfItem(atPath: helperPath) else {
            return "Could not read helper permissions"
        }

        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        if (perms & 0o4000) == 0 {
            return String(format: "Missing setuid bit (%04o)", perms)
        }

        let owner = attrs[.ownerAccountName] as? String
        if owner != "root" {
            return "Owner is \(owner ?? "unknown"), expected root"
        }

        let group = attrs[.groupOwnerAccountName] as? String
        if group != "wheel" {
            return "Group is \(group ?? "unknown"), expected wheel"
        }

        return nil
    }
}
