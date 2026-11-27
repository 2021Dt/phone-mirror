// Build with clang -Os -fobjc-arc -framework AppKit -framework Carbon.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <unistd.h>

static pid_t mirrorPID;
static NSURL *adbURL;
static NSURL *workerURL;
static NSTask *activeTransfer;
static NSString *serial;
static const OSType signature = 'Phne';
enum { PhoneHome = 1, PhoneRecents, PhoneSend, PhoneGet, PhoneFolder };
static struct {
    UInt32 code;
    const char *label;
    EventHotKeyRef registration;
} shortcuts[] = {
    { kVK_ANSI_1, "⌘1", NULL }, { kVK_ANSI_2, "⌘2", NULL },
    { kVK_ANSI_U, "⌘U", NULL }, { kVK_ANSI_D, "⌘D", NULL },
    { kVK_ANSI_Comma, "⌘,", NULL }
};

static BOOL mirrorIsActive(void) {
    return getppid() == mirrorPID &&
           NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == mirrorPID;
}

static void updateRegistration(void) {
    static BOOL announced = NO;
    BOOL active = mirrorIsActive();
    BOOL allRegistered = active;
    for (UInt32 i = 0; i < sizeof(shortcuts) / sizeof(shortcuts[0]); ++i) {
        if (active && !shortcuts[i].registration) {
            EventHotKeyID key = { signature, i + 1 };
            OSStatus status = RegisterEventHotKey(shortcuts[i].code, cmdKey, key,
                GetEventDispatcherTarget(), 0, &shortcuts[i].registration);
            if (status != noErr) {
                fprintf(stderr, "phone：无法启用 %s（macOS 错误 %d）。\n",
                        shortcuts[i].label, (int)status);
            }
        } else if (!active && shortcuts[i].registration) {
            UnregisterEventHotKey(shortcuts[i].registration);
            shortcuts[i].registration = NULL;
        }
        if (!shortcuts[i].registration) allRegistered = NO;
    }
    if (!announced && allRegistered) {
        fprintf(stderr, "phone · 投屏窗口的导航和文件快捷键已启用。\n");
        announced = YES;
    }
}

static void startTransfer(NSString *mode) {
    if (activeTransfer) return;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-f", workerURL.path, mode, nil];
    if (![mode isEqualToString:@"folder"]) [args addObjectsFromArray:@[adbURL.path, serial]];
    task.arguments = args;
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PHONE_WINDOW_FEEDBACK"] = @"1";
    task.environment = environment;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (activeTransfer == finished) activeTransfer = nil;
        });
    };
    NSError *error = nil;
    activeTransfer = task;
    if (![task launchAndReturnError:&error]) {
        activeTransfer = nil;
        NSBeep();
        fprintf(stderr, "phone：无法打开文件选择器（%s）。\n", error.localizedDescription.UTF8String);
    }
}

static OSStatus handleShortcut(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID key;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                        NULL, sizeof(key), NULL, &key);
    if (status != noErr || key.signature != signature || !mirrorIsActive()) {
        return eventNotHandledErr;
    }
    NSString *action;
    switch (key.id) {
        case PhoneHome: action = @"KEYCODE_HOME"; break;
        case PhoneRecents: action = @"KEYCODE_APP_SWITCH"; break;
        case PhoneSend: startTransfer(@"send"); return noErr;
        case PhoneGet: startTransfer(@"get"); return noErr;
        case PhoneFolder: startTransfer(@"folder"); return noErr;
        default: return eventNotHandledErr;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = adbURL;
    task.arguments = @[@"-s", serial, @"shell", @"input", @"keyevent", action];
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        fprintf(stderr, "phone：无法运行 adb（%s）。\n", error.localizedDescription.UTF8String);
    }
    return noErr;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        // The launch subshell starts this helper, then execs scrcpy with the same PID.
        mirrorPID = getppid();
        if (mirrorPID <= 1) return 0;
        adbURL = [NSURL fileURLWithPath:@(argv[1])];
        serial = @(argv[2]);
        NSURL *helperURL = [NSURL fileURLWithPath:@(argv[0])].URLByResolvingSymlinksInPath;
        workerURL = [helperURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"phone-transfer.zsh"];
        [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyProhibited];
        dispatch_source_t parentExit = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC,
            (uintptr_t)mirrorPID, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
        if (!parentExit) return 1;
        dispatch_source_set_event_handler(parentExit, ^{ [NSApp terminate:nil]; });
        dispatch_resume(parentExit);
        if (getppid() != mirrorPID) return 0;

        EventTypeSpec shortcutPressed = { kEventClassKeyboard, kEventHotKeyPressed };
        OSStatus status = InstallEventHandler(GetEventDispatcherTarget(), handleShortcut,
                                              1, &shortcutPressed, NULL, NULL);
        if (status != noErr) {
            fprintf(stderr, "phone：无法启用投屏快捷键（macOS 错误 %d）。\n", (int)status);
            return 1;
        }
        NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
        id observer = [center addObserverForName:NSWorkspaceDidActivateApplicationNotification
            object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) { updateRegistration(); }];
        updateRegistration();
        [NSApp run];
        [center removeObserver:observer];
        dispatch_source_cancel(parentExit);
    }
    return 0;
}
