/*
 * ipatcher-helper — setuid root helper for iPatcher
 *
 * Installed to /var/jb/usr/local/bin/ipatcher-helper with chmod 4755 (setuid root).
 * The iPatcher app spawns this binary for operations that require root:
 *   install <src_dylib> <src_plist> <dest_dir>
 *   uninstall <dest_dir>
 *   respring
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <copyfile.h>
#include <signal.h>
#include <sys/sysctl.h>
#include <libgen.h>
#include <errno.h>
#include <spawn.h>
#include <sys/wait.h>

#define SUBSTRATE_BASE "/var/jb/Library/MobileSubstrate/DynamicLibraries"
#define HELPER_VERSION "1.0.0"

static int mkdirp(const char *path, mode_t mode) {
    char tmp[1024];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';

    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, mode);
            *p = '/';
        }
    }
    return mkdir(tmp, mode);
}

static int copy_file(const char *src, const char *dst, mode_t mode) {
    unlink(dst);
    if (copyfile(src, dst, NULL, COPYFILE_ALL) != 0) {
        fprintf(stderr, "copyfile %s -> %s: %s\n", src, dst, strerror(errno));
        return -1;
    }
    chmod(dst, mode);
    return 0;
}

static int cmd_install(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "usage: install <dylib_src> <plist_src> <dest_dir>\n");
        return 1;
    }
    const char *dylib_src = argv[2];
    const char *plist_src = argv[3];
    const char *dest_dir  = argv[4];

    /* Validate source files exist */
    if (access(dylib_src, R_OK) != 0) {
        fprintf(stderr, "source dylib not found: %s\n", dylib_src);
        return 1;
    }
    if (access(plist_src, R_OK) != 0) {
        fprintf(stderr, "source plist not found: %s\n", plist_src);
        return 1;
    }

    /* Create destination directory */
    mkdirp(dest_dir, 0755);

    /* Build destination paths */
    char dylib_dst[1024], plist_dst[1024];
    snprintf(dylib_dst, sizeof(dylib_dst), "%s/iPatcher.dylib", dest_dir);
    snprintf(plist_dst, sizeof(plist_dst), "%s/iPatcher.plist", dest_dir);

    if (copy_file(dylib_src, dylib_dst, 0755) != 0) return 1;
    if (copy_file(plist_src, plist_dst, 0644) != 0) return 1;

    /* Re-sign the dylib with ldid so it has a valid cdhash */
    const char *ldid_path = "/var/jb/usr/bin/ldid";
    if (access(ldid_path, X_OK) == 0) {
        char *ldid_argv[] = { (char *)ldid_path, "-s", (char *)dylib_dst, NULL };
        pid_t pid;
        int ret = posix_spawn(&pid, ldid_path, NULL, NULL, ldid_argv, NULL);
        if (ret == 0) {
            int status;
            waitpid(pid, &status, 0);
            if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
                fprintf(stderr, "ldid signing failed (exit %d)\n",
                        WIFEXITED(status) ? WEXITSTATUS(status) : -1);
                return 1;
            }
        } else {
            fprintf(stderr, "posix_spawn ldid failed: %s\n", strerror(ret));
            return 1;
        }
    } else {
        fprintf(stderr, "warning: ldid not found at %s, dylib may fail to load\n", ldid_path);
    }

    printf("ok\n");
    return 0;
}

static int cmd_uninstall(int argc, char *argv[]) {
    const char *dest_dir = (argc >= 3) ? argv[2] : SUBSTRATE_BASE;

    char dylib_dst[1024], plist_dst[1024];
    snprintf(dylib_dst, sizeof(dylib_dst), "%s/iPatcher.dylib", dest_dir);
    snprintf(plist_dst, sizeof(plist_dst), "%s/iPatcher.plist", dest_dir);

    unlink(dylib_dst);
    unlink(plist_dst);

    printf("ok\n");
    return 0;
}

static int cmd_respring(void) {
    /* Find SpringBoard PID via sysctl and kill it */
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    sysctl(mib, 4, NULL, &size, NULL, 0);

    struct kinfo_proc *procs = malloc(size);
    if (!procs) return 1;
    sysctl(mib, 4, procs, &size, NULL, 0);

    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) {
            kill(procs[i].kp_proc.p_pid, SIGTERM);
            free(procs);
            printf("ok\n");
            return 0;
        }
    }

    free(procs);
    fprintf(stderr, "SpringBoard not found\n");
    return 1;
}

int main(int argc, char *argv[]) {
    /* Elevate to real root — required for setuid binaries */
    setuid(0);
    setgid(0);

    if (argc < 2) {
        fprintf(stderr, "ipatcher-helper %s\n", HELPER_VERSION);
        fprintf(stderr, "commands: install, uninstall, respring\n");
        return 1;
    }

    if (strcmp(argv[1], "install") == 0)   return cmd_install(argc, argv);
    if (strcmp(argv[1], "uninstall") == 0) return cmd_uninstall(argc, argv);
    if (strcmp(argv[1], "respring") == 0)  return cmd_respring();

    fprintf(stderr, "unknown command: %s\n", argv[1]);
    return 1;
}
