/*
 * ipatcher-cli — Debug CLI that replicates all iPatcher app actions.
 *
 * Run on device via SSH:
 *   ipatcher-cli status          — check helper, tweak, patches
 *   ipatcher-cli install         — install tweak via helper (same as app)
 *   ipatcher-cli uninstall       — uninstall tweak via helper
 *   ipatcher-cli respring        — respring via helper
 *   ipatcher-cli apps            — list discovered apps (3rd-party)
 *   ipatcher-cli apps --all      — list all apps including system
 *   ipatcher-cli patches         — list all patch profiles
 *   ipatcher-cli patches <bid>   — show patches for a bundle ID
 *   ipatcher-cli helper-test     — test helper binary directly
 *
 * Build: compiled as part of `make cli` and deployed to device.
 * Run as mobile to simulate app context: su mobile -c '/var/jb/usr/local/bin/ipatcher-cli status'
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/sysctl.h>
#import <signal.h>

// --- Constants (mirrors app) ---
#define HELPER_PATH     "/var/jb/usr/local/libexec/ipatcher-helper"
#define SUBSTRATE_PATH  "/var/jb/Library/MobileSubstrate/DynamicLibraries"
#define TWEAKLOADER_PATH "/var/jb/usr/lib/TweakLoader.dylib"
#define PATCHES_DIR     "/var/jb/var/mobile/Library/iPatcher/patches"
#define APP_BUNDLE_PATH "/var/jb/Applications/iPatcher.app"
#define TWEAK_PAYLOAD   APP_BUNDLE_PATH "/TweakPayload"

// --- Colors ---
#define C_RED     "\033[31m"
#define C_GREEN   "\033[32m"
#define C_YELLOW  "\033[33m"
#define C_CYAN    "\033[36m"
#define C_BOLD    "\033[1m"
#define C_RESET   "\033[0m"

#define OK(msg)   printf(C_GREEN "  ✓ " C_RESET "%s\n", msg)
#define FAIL(msg) printf(C_RED   "  ✗ " C_RESET "%s\n", msg)
#define INFO(msg) printf(C_CYAN  "  → " C_RESET "%s\n", msg)

// --- Helper execution (mirrors TweakInstaller.runHelper) ---
static int run_helper(const char *argv[], char *out, size_t out_sz) {
    int pipefd[2], errfd[2];
    pipe(pipefd);
    pipe(errfd);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errfd[1], STDERR_FILENO);

    pid_t pid;
    int ret = posix_spawn(&pid, HELPER_PATH, &actions, NULL, (char **)argv, NULL);
    posix_spawn_file_actions_destroy(&actions);

    close(pipefd[1]);
    close(errfd[1]);

    if (ret != 0) {
        snprintf(out, out_sz, "posix_spawn failed: %d", ret);
        close(pipefd[0]);
        close(errfd[0]);
        return -1;
    }

    int status;
    waitpid(pid, &status, 0);

    ssize_t n = read(pipefd[0], out, out_sz - 1);
    if (n > 0) out[n] = '\0';
    else {
        n = read(errfd[0], out, out_sz - 1);
        if (n > 0) out[n] = '\0';
        else out[0] = '\0';
    }
    close(pipefd[0]);
    close(errfd[0]);

    // Trim trailing newline
    size_t len = strlen(out);
    while (len > 0 && (out[len-1] == '\n' || out[len-1] == '\r')) out[--len] = '\0';

    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return -1;
}

// --- cmd: status ---
static int cmd_status(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    printf(C_BOLD "\n  iPatcher Status\n" C_RESET);
    printf("  ───────────────────────────────────────\n");

    // Helper
    printf("\n  " C_BOLD "Helper:" C_RESET "\n");
    BOOL helperExists = [fm fileExistsAtPath:@HELPER_PATH];
    BOOL helperExec   = [fm isExecutableFileAtPath:@HELPER_PATH];
    if (helperExists && helperExec) {
        OK(HELPER_PATH " (setuid root)");
        // Verify setuid
        NSDictionary *attrs = [fm attributesOfItemAtPath:@HELPER_PATH error:nil];
        NSUInteger perms = [attrs[NSFilePosixPermissions] unsignedIntegerValue];
        if (perms & 04000) {
            char buf[256];
            snprintf(buf, sizeof(buf), "permissions: %04lo (setuid ✓)", (unsigned long)perms);
            OK(buf);
        } else {
            char buf[256];
            snprintf(buf, sizeof(buf), "permissions: %04lo — MISSING SETUID BIT!", (unsigned long)perms);
            FAIL(buf);
        }
    } else if (helperExists) {
        FAIL(HELPER_PATH " (exists but not executable)");
    } else {
        FAIL(HELPER_PATH " (not found)");
    }

    // Tweak dylib
    printf("\n  " C_BOLD "Tweak:" C_RESET "\n");
    NSString *dylibPath = @SUBSTRATE_PATH "/iPatcher.dylib";
    NSString *plistPath = @SUBSTRATE_PATH "/iPatcher.plist";
    NSString *loaderPath = @TWEAKLOADER_PATH;
    if ([fm fileExistsAtPath:dylibPath]) {
        NSDictionary *a = [fm attributesOfItemAtPath:dylibPath error:nil];
        char buf[512];
        snprintf(buf, sizeof(buf), "%s (%llu bytes)", dylibPath.UTF8String,
                 [a[NSFileSize] unsignedLongLongValue]);
        OK(buf);
    } else {
        FAIL("iPatcher.dylib not installed");
    }
    if ([fm fileExistsAtPath:plistPath]) {
        OK("iPatcher.plist present");
    } else {
        FAIL("iPatcher.plist not found");
    }
    if ([fm fileExistsAtPath:loaderPath]) {
        OK(TWEAKLOADER_PATH " present");
    } else {
        FAIL(TWEAKLOADER_PATH " missing");
    }

    // App bundle
    printf("\n  " C_BOLD "App Bundle:" C_RESET "\n");
    NSString *appBin = @APP_BUNDLE_PATH "/iPatcher";
    if ([fm fileExistsAtPath:appBin]) {
        OK(APP_BUNDLE_PATH);
    } else {
        FAIL(APP_BUNDLE_PATH " (not found)");
    }
    NSString *tweakPayloadDylib = @TWEAK_PAYLOAD "/iPatcher.dylib";
    NSString *tweakPayloadPlist = @TWEAK_PAYLOAD "/iPatcher.plist";
    if ([fm fileExistsAtPath:tweakPayloadDylib] && [fm fileExistsAtPath:tweakPayloadPlist]) {
        OK("TweakPayload/iPatcher.dylib + .plist present");
    } else {
        FAIL("TweakPayload missing or incomplete");
    }

    // Patches directory
    printf("\n  " C_BOLD "Patches:" C_RESET "\n");
    NSArray *patches = [fm contentsOfDirectoryAtPath:@PATCHES_DIR error:nil];
    NSArray *jsonFiles = [patches filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"self ENDSWITH '.json'"]];
    if (jsonFiles.count > 0) {
        char buf[128];
        snprintf(buf, sizeof(buf), "%lu profile(s) in %s", (unsigned long)jsonFiles.count, PATCHES_DIR);
        OK(buf);
        for (NSString *f in jsonFiles) {
            printf("       %s\n", f.UTF8String);
        }
    } else {
        INFO("No patch profiles yet");
    }

    printf("\n");
    return 0;
}

// --- cmd: install ---
static int cmd_install(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    printf(C_BOLD "Installing tweak via helper...\n" C_RESET);

    if (![fm isExecutableFileAtPath:@HELPER_PATH]) {
        FAIL("Helper not found or not executable at " HELPER_PATH);
        return 1;
    }

    NSString *dylibSrc = @TWEAK_PAYLOAD "/iPatcher.dylib";
    NSString *plistSrc = @TWEAK_PAYLOAD "/iPatcher.plist";

    if (![fm fileExistsAtPath:dylibSrc]) {
        FAIL("Source dylib not found: TweakPayload/iPatcher.dylib");
        return 1;
    }
    if (![fm fileExistsAtPath:plistSrc]) {
        FAIL("Source plist not found: TweakPayload/iPatcher.plist");
        return 1;
    }

    INFO("Spawning helper: install");
    printf("    src dylib: %s\n", dylibSrc.UTF8String);
    printf("    src plist: %s\n", plistSrc.UTF8String);
    printf("    dest dir:  %s\n", SUBSTRATE_PATH);

    const char *argv[] = { HELPER_PATH, "install",
        dylibSrc.UTF8String, plistSrc.UTF8String, SUBSTRATE_PATH, NULL };
    char output[1024];
    int code = run_helper(argv, output, sizeof(output));

    printf("    exit=%d output=\"%s\"\n", code, output);
    if (code == 0) {
        OK("Tweak installed successfully");
    } else {
        FAIL("Install failed");
    }
    return code;
}

// --- cmd: uninstall ---
static int cmd_uninstall(void) {
    printf(C_BOLD "Uninstalling tweak via helper...\n" C_RESET);

    if (![[NSFileManager defaultManager] isExecutableFileAtPath:@HELPER_PATH]) {
        FAIL("Helper not found at " HELPER_PATH);
        return 1;
    }

    INFO("Spawning helper: uninstall");
    const char *argv[] = { HELPER_PATH, "uninstall", SUBSTRATE_PATH, NULL };
    char output[1024];
    int code = run_helper(argv, output, sizeof(output));

    printf("    exit=%d output=\"%s\"\n", code, output);
    if (code == 0) {
        OK("Tweak uninstalled");
    } else {
        FAIL("Uninstall failed");
    }
    return code;
}

// --- cmd: respring ---
static int cmd_respring(void) {
    printf(C_BOLD "Respringing...\n" C_RESET);

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@HELPER_PATH]) {
        INFO("Using helper for respring");
        const char *argv[] = { HELPER_PATH, "respring", NULL };
        char output[1024];
        int code = run_helper(argv, output, sizeof(output));
        printf("    exit=%d output=\"%s\"\n", code, output);
        return code;
    }

    // Fallback: direct kill (mirrors app's killSpringBoard)
    INFO("Helper not found, using direct kill (fallback)");
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    sysctl(mib, 4, NULL, &size, NULL, 0);
    struct kinfo_proc *procs = malloc(size);
    sysctl(mib, 4, procs, &size, NULL, 0);
    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) {
            printf("    SpringBoard PID: %d\n", procs[i].kp_proc.p_pid);
            int r = kill(procs[i].kp_proc.p_pid, SIGTERM);
            printf("    kill() returned: %d (errno=%d)\n", r, r == 0 ? 0 : errno);
            free(procs);
            return r;
        }
    }
    free(procs);
    FAIL("SpringBoard not found");
    return 1;
}

// --- cmd: apps ---
static int cmd_apps(BOOL includeSystem) {
    printf(C_BOLD "Discovering apps%s...\n" C_RESET,
           includeSystem ? " (including system)" : "");

    // Try LSApplicationWorkspace (same as app)
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) {
        FAIL("LSApplicationWorkspace not available");
        return 1;
    }

    id ws = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
    NSArray *allApps = [ws performSelector:NSSelectorFromString(@"allApplications")];

    int total = 0, shown = 0;
    for (id proxy in allApps) {
        total++;
        NSString *bid = [proxy performSelector:NSSelectorFromString(@"applicationIdentifier")];
        if (!bid) continue;
        if (!includeSystem && [bid hasPrefix:@"com.apple."]) continue;

        NSString *name = @"?";
        if ([proxy respondsToSelector:NSSelectorFromString(@"localizedName")]) {
            name = [proxy performSelector:NSSelectorFromString(@"localizedName")] ?: bid;
        }
        NSString *ver = @"?";
        if ([proxy respondsToSelector:NSSelectorFromString(@"shortVersionString")]) {
            ver = [proxy performSelector:NSSelectorFromString(@"shortVersionString")] ?: @"?";
        }

        // Check for patches
        NSString *patchFile = [NSString stringWithFormat:@"%s/%@.json", PATCHES_DIR, bid];
        BOOL hasPatches = [[NSFileManager defaultManager] fileExistsAtPath:patchFile];

        printf("  %s%-40s%s  %s  v%s%s\n",
               hasPatches ? C_GREEN : "",
               bid.UTF8String,
               hasPatches ? C_RESET : "",
               name.UTF8String,
               ver.UTF8String,
               hasPatches ? C_YELLOW " [patched]" C_RESET : "");
        shown++;
    }

    printf("\n  %d apps shown (%d total on device)\n\n", shown, total);
    return 0;
}

// --- cmd: patches ---
static int cmd_patches(const char *filterBID) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:@PATCHES_DIR error:nil];

    if (!files || files.count == 0) {
        INFO("No patch profiles in " PATCHES_DIR);
        return 0;
    }

    printf(C_BOLD "Patch Profiles:\n" C_RESET);

    for (NSString *filename in files) {
        if (![filename hasSuffix:@".json"]) continue;

        NSString *path = [@PATCHES_DIR stringByAppendingPathComponent:filename];
        NSData *data = [fm contentsAtPath:path];
        if (!data) continue;

        NSError *err = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (!json) {
            printf("  " C_RED "✗ %s: parse error: %s" C_RESET "\n",
                   filename.UTF8String, err.localizedDescription.UTF8String);
            continue;
        }

        NSString *bid = json[@"bundleID"] ?: @"?";
        if (filterBID && strcmp(filterBID, bid.UTF8String) != 0) continue;

        NSString *appName = json[@"appName"] ?: bid;
        BOOL enabled = [json[@"enabled"] boolValue];
        NSArray *patches = json[@"patches"] ?: @[];

        printf("\n  " C_BOLD "%s" C_RESET " (%s)\n", appName.UTF8String, bid.UTF8String);
        printf("  enabled: %s%s%s | %lu patch(es)\n",
               enabled ? C_GREEN : C_RED,
               enabled ? "yes" : "no",
               C_RESET,
               (unsigned long)patches.count);

        for (NSDictionary *p in patches) {
            NSString *pname = p[@"name"] ?: @"unnamed";
            BOOL penabled = [p[@"enabled"] boolValue];
            NSString *pattern = p[@"pattern"] ?: @"";
            NSString *replacement = p[@"replacement"] ?: @"";
            int offset = [p[@"offset"] intValue];

            printf("    %s%s%s %s\n",
                   penabled ? C_GREEN "●" : C_RED "○",
                   C_RESET, "", pname.UTF8String);
            printf("      find:    %s\n", pattern.UTF8String);
            printf("      replace: %s\n", replacement.UTF8String);
            if (offset != 0) printf("      offset:  %d\n", offset);
        }
    }
    printf("\n");
    return 0;
}

// --- cmd: helper-test ---
static int cmd_helper_test(void) {
    printf(C_BOLD "Testing helper binary...\n\n" C_RESET);

    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Existence
    if (![fm fileExistsAtPath:@HELPER_PATH]) {
        FAIL("Not found: " HELPER_PATH);
        return 1;
    }
    OK("Found: " HELPER_PATH);

    // 2. Executable
    if (![fm isExecutableFileAtPath:@HELPER_PATH]) {
        FAIL("Not executable");
        return 1;
    }
    OK("Executable");

    // 3. Setuid
    NSDictionary *attrs = [fm attributesOfItemAtPath:@HELPER_PATH error:nil];
    NSUInteger perms = [attrs[NSFilePosixPermissions] unsignedIntegerValue];
    if (perms & 04000) {
        char buf[64];
        snprintf(buf, sizeof(buf), "Setuid bit set (%04lo)", (unsigned long)perms);
        OK(buf);
    } else {
        char buf[128];
        snprintf(buf, sizeof(buf), "NO SETUID (%04lo) — run: chmod 4755 %s", (unsigned long)perms, HELPER_PATH);
        FAIL(buf);
    }

    // 4. Owner
    NSString *owner = attrs[NSFileOwnerAccountName];
    if ([owner isEqualToString:@"root"]) {
        OK("Owner: root");
    } else {
        char buf[128];
        snprintf(buf, sizeof(buf), "Owner: %s (should be root)", owner.UTF8String);
        FAIL(buf);
    }

    // 5. Run --help
    printf("\n  " C_BOLD "Spawn test (no args):" C_RESET "\n");
    const char *argv[] = { HELPER_PATH, NULL };
    char output[1024];
    int code = run_helper(argv, output, sizeof(output));
    printf("    exit=%d output=\"%s\"\n", code, output);

    // 6. Dry run: install then uninstall
    printf("\n  " C_BOLD "Round-trip test: install → verify → uninstall → verify" C_RESET "\n");

    NSString *dylibSrc = @TWEAK_PAYLOAD "/iPatcher.dylib";
    NSString *plistSrc = @TWEAK_PAYLOAD "/iPatcher.plist";
    NSString *dylibDst = @SUBSTRATE_PATH "/iPatcher.dylib";

    if (![fm fileExistsAtPath:dylibSrc]) {
        FAIL("TweakPayload not found — skip round-trip");
        return 0;
    }

    // Install
    const char *iargv[] = { HELPER_PATH, "install",
        dylibSrc.UTF8String, plistSrc.UTF8String, SUBSTRATE_PATH, NULL };
    code = run_helper(iargv, output, sizeof(output));
    printf("    install: exit=%d output=\"%s\"\n", code, output);
    if ([fm fileExistsAtPath:dylibDst]) {
        OK("Dylib present after install");
    } else {
        FAIL("Dylib NOT present after install");
    }

    // Uninstall
    const char *uargv[] = { HELPER_PATH, "uninstall", SUBSTRATE_PATH, NULL };
    code = run_helper(uargv, output, sizeof(output));
    printf("    uninstall: exit=%d output=\"%s\"\n", code, output);
    if (![fm fileExistsAtPath:dylibDst]) {
        OK("Dylib removed after uninstall");
    } else {
        FAIL("Dylib STILL present after uninstall");
    }

    printf("\n");
    return 0;
}

// --- Usage ---
static void usage(void) {
    fprintf(stderr,
        "ipatcher-cli — debug tool (run as mobile to simulate app)\n\n"
        "Usage:\n"
        "  ipatcher-cli status            Check helper, tweak, patches\n"
        "  ipatcher-cli install           Install tweak via helper\n"
        "  ipatcher-cli uninstall         Uninstall tweak via helper\n"
        "  ipatcher-cli respring          Respring via helper\n"
        "  ipatcher-cli apps [--all]      List discovered apps\n"
        "  ipatcher-cli patches [<bid>]   List patch profiles\n"
        "  ipatcher-cli helper-test       Full helper diagnostic\n"
    );
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { usage(); return 1; }

        const char *cmd = argv[1];

        if (strcmp(cmd, "status") == 0)       return cmd_status();
        if (strcmp(cmd, "install") == 0)      return cmd_install();
        if (strcmp(cmd, "uninstall") == 0)    return cmd_uninstall();
        if (strcmp(cmd, "respring") == 0)     return cmd_respring();
        if (strcmp(cmd, "helper-test") == 0)  return cmd_helper_test();
        if (strcmp(cmd, "apps") == 0) {
            BOOL all = (argc >= 3 && strcmp(argv[2], "--all") == 0);
            return cmd_apps(all);
        }
        if (strcmp(cmd, "patches") == 0) {
            return cmd_patches(argc >= 3 ? argv[2] : NULL);
        }

        fprintf(stderr, "Unknown command: %s\n\n", cmd);
        usage();
        return 1;
    }
}
