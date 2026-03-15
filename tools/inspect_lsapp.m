#import <Foundation/Foundation.h>
#import <objc/runtime.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!wsClass) {
            printf("LSApplicationWorkspace not found\n");
            return 1;
        }

        id ws = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
        NSArray *apps = [ws performSelector:NSSelectorFromString(@"allApplications")];

        printf("App count: %lu\n", (unsigned long)apps.count);
        if (apps.count == 0) return 0;

        id first = apps[0];
        printf("Class: %s\n", class_getName([first class]));

        // Dump instance methods
        unsigned int count = 0;
        Class cls = [first class];
        while (cls) {
            Method *methods = class_copyMethodList(cls, &count);
            printf("\n--- %s (%u methods) ---\n", class_getName(cls), count);
            for (unsigned int i = 0; i < count; i++) {
                SEL sel = method_getName(methods[i]);
                const char *name = sel_getName(sel);
                // Filter for interesting selectors
                if (strstr(name, "undle") || strstr(name, "ame") ||
                    strstr(name, "ersion") || strstr(name, "ath") ||
                    strstr(name, "con") || strstr(name, "URL") ||
                    strstr(name, "dentif") || strstr(name, "esource") ||
                    strstr(name, "ocal")) {
                    printf("  %s\n", name);
                }
            }
            free(methods);
            cls = class_getSuperclass(cls);
            if (cls == [NSObject class]) break;
        }

        // Try common selectors on first app
        printf("\n--- Testing selectors on first app ---\n");
        SEL selectors[] = {
            NSSelectorFromString(@"applicationIdentifier"),
            NSSelectorFromString(@"bundleIdentifier"),
            NSSelectorFromString(@"localizedName"),
            NSSelectorFromString(@"itemName"),
            NSSelectorFromString(@"shortVersionString"),
            NSSelectorFromString(@"bundleVersion"),
            NSSelectorFromString(@"resourcesDirectoryURL"),
            NSSelectorFromString(@"bundleURL"),
            NSSelectorFromString(@"bundleContainerURL"),
            NSSelectorFromString(@"dataContainerURL"),
        };
        const char *names[] = {
            "applicationIdentifier", "bundleIdentifier",
            "localizedName", "itemName",
            "shortVersionString", "bundleVersion",
            "resourcesDirectoryURL", "bundleURL",
            "bundleContainerURL", "dataContainerURL",
        };
        for (int i = 0; i < sizeof(selectors)/sizeof(selectors[0]); i++) {
            BOOL responds = [first respondsToSelector:selectors[i]];
            printf("  %s: %s", names[i], responds ? "YES" : "NO");
            if (responds) {
                id val = [first performSelector:selectors[i]];
                printf(" -> %s", [[val description] UTF8String]);
            }
            printf("\n");
        }
    }
    return 0;
}
