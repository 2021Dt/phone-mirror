// Build with clang -Os -fobjc-arc -framework AppKit -framework Carbon.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <unistd.h>

static pid_t mirrorPID;
static NSURL *adbURL;
static NSString *serial;
static const OSType signature = 'Phne';
static const UInt32 digitKeys[] = { kVK_ANSI_1, kVK_ANSI_2 };
static EventHotKeyRef registeredKeys[2];

static BOOL mirrorIsActive(void) {
    return getppid() == mirrorPID &&
           NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == mirrorPID;
}

static void updateRegistration(void) {
    static BOOL announced = NO;
    BOOL active = mirrorIsActive();
    for (UInt32 i = 0; i < 2; ++i) {
        if (active && !registeredKeys[i]) {
            EventHotKeyID key = { signature, i + 1 };
            OSStatus status = RegisterEventHotKey(digitKeys[i], cmdKey, key,
                GetEventDispatcherTarget(), 0, &registeredKeys[i]);
            if (status != noErr) {
                fprintf(stderr, "phone：无法启用 ⌘%u（macOS 错误 %d）。\n",
                        (unsigned)key.id, (int)status);
            }
        } else if (!active && registeredKeys[i]) {
            UnregisterEventHotKey(registeredKeys[i]);
            registeredKeys[i] = NULL;
        }
    }
    if (!announced && registeredKeys[0] && registeredKeys[1]) {
        fprintf(stderr, "phone · 当前投屏已启用 ⌘1 主屏幕 / ⌘2 最近任务。\n");
        announced = YES;
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
        case 1: action = @"KEYCODE_HOME"; break;
        case 2: action = @"KEYCODE_APP_SWITCH"; break;
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
            fprintf(stderr, "phone：无法启用投屏导航快捷键（macOS 错误 %d）。\n", (int)status);
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
