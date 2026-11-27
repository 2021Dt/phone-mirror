// Run with osascript -l JavaScript; the Zsh caller handles all transfers.
ObjC.import("Foundation");

function readDirectory(listingPath) {
    const listing = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(
        listingPath, $.NSUTF8StringEncoding, null
    ));
    if (typeof listing !== "string") throw new Error("无法读取手机文件列表。");
    const records = listing.split("\0");
    if (records[records.length - 1] === "") records.pop();
    const entries = records.map(function (record) {
        const kind = record.charAt(0);
        const name = record.slice(1);
        if ((kind !== "D" && kind !== "F") || !name || name === "." || name === ".." || name.includes("/"))
            throw new Error("手机文件列表格式有误。");
        // Escape line breaks, tabs and backslashes so each item occupies one row.
        const visibleName = JSON.stringify(name).slice(1, -1);
        return { kind: kind, name: name,
            label: (kind === "D" ? "📁 " : "📄 ") + visibleName };
    });
    entries.sort(function (a, b) {
        if (a.kind !== b.kind) return a.kind === "D" ? -1 : 1;
        return a.name.localeCompare(b.name);
    });
    return entries;
}

function writeSelection(selectionPath, paths) {
    const records = paths.length ? paths.join("\0") + "\0" : "";
    if (!$(records).writeToFileAtomicallyEncodingError(selectionPath, true, $.NSUTF8StringEncoding, $()))
        throw new Error("无法保存所选文件列表。");
}

function chooseMacFiles() {
    ObjC.import("AppKit");
    const application = $.NSApplication.sharedApplication;
    application.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
    const panel = $.NSOpenPanel.openPanel;
    panel.canChooseFiles = true;
    panel.canChooseDirectories = false;
    panel.allowsMultipleSelection = true;
    panel.message = "选择发送到手机「下载」的文件，可按 ⌘ 或 Shift 多选。";
    panel.prompt = "发送";
    application.activateIgnoringOtherApps(true);
    if (Number(panel.runModal) !== Number($.NSModalResponseOK)) return [];
    const urls = panel.URLs;
    const paths = [];
    for (let i = 0; i < urls.count; i++) paths.push(ObjC.unwrap(urls.objectAtIndex(i).path));
    return paths;
}

function choosePhoneFiles(adbPath, serial, workerPath, listingPath) {
    ObjC.import("AppKit");
    const application = $.NSApplication.sharedApplication;
    application.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
    const root = "/sdcard/";
    let directory = root + "Download/", entries = [], selectedFiles = [];
    let pending = null, timer = null, retryDirectory = "";

    const rect = $.NSMakeRect;
    const window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
        rect(0, 0, 520, 360), $.NSWindowStyleMaskTitled | $.NSWindowStyleMaskClosable,
        $.NSBackingStoreBuffered, false
    );
    window.title = "从手机取文件";
    window.releasedWhenClosed = false;
    function button(title, x, y, width, action) {
        const control = $.NSButton.alloc.initWithFrame(rect(x, y, width, 32));
        control.bezelStyle = $.NSBezelStyleRounded;
        control.title = title;
        control.action = action;
        window.contentView.addSubview(control);
        return control;
    }
    function label(x, y, width) {
        const field = $.NSTextField.labelWithString("");
        field.frame = rect(x, y, width, 20);
        field.lineBreakMode = $.NSLineBreakByTruncatingMiddle;
        window.contentView.addSubview(field);
        return field;
    }
    const up = button("上一级", 12, 314, 88, "goUp:");
    const location = label(107, 320, 395);
    const status = label(16, 16, 305);
    const cancel = button("取消", 324, 9, 76, "cancelPicker:");
    cancel.keyEquivalent = "\u001b";
    const primary = button("选择", 399, 9, 108, "openSelection:");
    primary.keyEquivalent = "\r";
    const frame = rect(14, 51, 492, 255);
    const table = $.NSTableView.alloc.initWithFrame(rect(0, 0, 492, 255));
    table.headerView = $();
    table.usesAlternatingRowBackgroundColors = true;
    table.allowsMultipleSelection = true;
    table.rowHeight = 25;
    const column = $.NSTableColumn.alloc.initWithIdentifier("name");
    column.width = 480;
    column.editable = false;
    table.addTableColumn(column);
    const scroll = $.NSScrollView.alloc.initWithFrame(frame);
    scroll.hasVerticalScroller = true;
    scroll.borderType = $.NSBezelBorder;
    scroll.documentView = table;
    window.contentView.addSubview(scroll);

    function selection() {
        const indexes = table.selectedRowIndexes;
        const files = [];
        let folder = null;
        for (let row = indexes.firstIndex; row < entries.length; row = indexes.indexGreaterThanIndex(row)) {
            const entry = entries[row];
            if (entry.kind === "F") files.push(directory + entry.name);
            else folder = entry;
        }
        return { files: files, folder: folder, count: Number(indexes.count) };
    }
    function updateControls() {
        const selected = selection();
        const singleFolder = selected.count === 1 && selected.folder;
        up.enabled = !pending && directory !== root;
        table.enabled = !pending;
        primary.enabled = !pending && Boolean(selected.files.length || singleFolder || (!selected.count && retryDirectory));
        primary.title = selected.files.length > 1 ? "下载 " + selected.files.length + " 项" :
            selected.files.length ? "下载" : singleFolder ? "打开文件夹" : (!selected.count && retryDirectory ? "重试" : "选择");
        if (!pending && !retryDirectory) {
            if (selected.folder && selected.files.length)
                status.stringValue = "将下载选中的文件，跳过文件夹。";
            else if (selected.folder && selected.count > 1)
                status.stringValue = "双击文件夹进入，再选择要下载的文件。";
            else status.stringValue = entries.length ? "双击打开，按 ⌘ 或 Shift 可多选文件。" : "这个文件夹是空的。";
        }
    }
    function loadDirectory(path) {
        if (pending) return;
        retryDirectory = "";
        status.stringValue = "正在读取…";
        const task = $.NSTask.alloc.init;
        task.launchPath = "/bin/zsh";
        task.arguments = ["-f", workerPath, "list", adbPath, serial, path];
        task.standardInput = $.NSFileHandle.fileHandleWithNullDevice;
        task.standardError = $.NSFileHandle.fileHandleWithNullDevice;
        const output = $.NSFileHandle.fileHandleForWritingAtPath(listingPath);
        try {
            output.truncateFileAtOffset(0);
            task.standardOutput = output;
            if (!task.launchAndReturnError($())) throw new Error("启动失败");
            pending = { task: task, path: path };
        } catch (error) {
            retryDirectory = path;
            status.stringValue = "无法读取目录，可重试或取消。";
        } finally {
            output.closeFile;
        }
        updateControls();
        if (pending) {
            timer = $.NSTimer.timerWithTimeIntervalTargetSelectorUserInfoRepeats(
                0.1, rows, "checkListing:", $(), true
            );
            $.NSRunLoop.mainRunLoop.addTimerForMode(timer, $.NSModalPanelRunLoopMode);
        }
    }
    function listingFinished() {
        if (!pending || pending.task.running) return;
        timer.invalidate;
        timer = null;
        const finished = pending;
        pending = null;
        try {
            if (finished.task.terminationStatus !== 0) throw new Error("目录不可读");
            const loaded = readDirectory(listingPath);
            table.deselectAll($());
            entries = loaded;
            directory = finished.path;
            table.reloadData;
            if (entries.length) table.scrollRowToVisible(0);
            location.stringValue = directory;
            location.toolTip = directory;
            status.toolTip = "";
            window.makeFirstResponder(table);
        } catch (error) {
            retryDirectory = finished.path;
            status.stringValue = "无法打开该目录，请检查连接或权限。";
            status.toolTip = finished.path;
        }
        updateControls();
    }
    function finish(files) {
        selectedFiles = files;
        application.stopModalWithCode(1);
    }
    ObjC.registerSubclass({
        name: "PhoneFileRows", superclass: "NSObject",
        protocols: ["NSTableViewDataSource", "NSTableViewDelegate", "NSWindowDelegate"],
        methods: {
            "numberOfRowsInTableView:": { implementation: function () { return entries.length; } },
            "tableView:objectValueForTableColumn:row:": {
                implementation: function (view, col, row) { return $(entries[row].label); }
            },
            "tableViewSelectionDidChange:": { implementation: updateControls },
            "openSelection:": { types: ["void", ["id"]], implementation: function () {
                if (pending) return;
                const selected = selection();
                if (selected.files.length) finish(selected.files);
                else if (selected.count === 1 && selected.folder) loadDirectory(directory + selected.folder.name + "/");
                else if (!selected.count && retryDirectory) loadDirectory(retryDirectory);
            } },
            "openRow:": { types: ["void", ["id"]], implementation: function (view) {
                const entry = entries[view.clickedRow];
                if (pending || !entry) return;
                if (entry.kind === "D") loadDirectory(directory + entry.name + "/");
                else finish([directory + entry.name]);
            } },
            "goUp:": { types: ["void", ["id"]], implementation: function () {
                if (directory !== root) loadDirectory(directory.replace(/[^/]+\/$/, ""));
            } },
            "cancelPicker:": { types: ["void", ["id"]], implementation: function () {
                application.stopModalWithCode(0);
            } },
            "windowShouldClose:": { implementation: function () {
                application.stopModalWithCode(0);
                return false;
            } },
            "checkListing:": { types: ["void", ["id"]], implementation: listingFinished }
        }
    });
    const rows = $.PhoneFileRows.alloc.init;
    table.dataSource = rows;
    table.delegate = rows;
    table.target = rows;
    table.doubleAction = "openRow:";
    up.target = primary.target = cancel.target = rows;
    window.delegate = rows;
    window.initialFirstResponder = table;
    location.stringValue = directory;
    if (!$.NSFileManager.defaultManager.createFileAtPathContentsAttributes(listingPath, $(), $()))
        throw new Error("无法创建目录列表暂存文件。");
    loadDirectory(directory);
    window.center;
    application.activateIgnoringOtherApps(true);
    window.makeKeyAndOrderFront($());
    try {
        const response = application.runModalForWindow(window);
        return Number(response) === 1 ? selectedFiles : [];
    } finally {
        if (timer) timer.invalidate;
        if (pending && pending.task.running) pending.task.terminate;
        window.orderOut($());
    }
}

function run(args) {
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    try {
        if (args[0] === "notify" && args.length === 2) {
            app.displayNotification(args[1], { withTitle: "phone 文件传输" });
            return "";
        }
        if (ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("PHONE_WINDOW_FEEDBACK")) === "1") {
            ObjC.import("AppKit");
            $.NSApplication.sharedApplication.activateIgnoringOtherApps(true);
        }
        if (args[0] === "error" && args.length === 2) {
            app.displayAlert("文件操作未完成", { message: args[1], as: "warning" });
            return "";
        }
        if (args[0] === "folder" && args.length === 1) {
            return app.chooseFolder({ withPrompt: "以后从手机下载的文件存到哪个 Mac 文件夹？" }).toString();
        }
        if (args[0] === "send" && args.length === 2) {
            writeSelection(args[1], chooseMacFiles());
            return "";
        }
        if (args[0] === "get" && args.length === 6) {
            writeSelection(args[5], choosePhoneFiles(args[1], args[2], args[3], args[4]));
            return "";
        }
        throw new Error("文件选择器参数有误。");
    } catch (error) {
        if (error.errorNumber === -128 || error.number === -128) return "";
        throw error;
    }
}
