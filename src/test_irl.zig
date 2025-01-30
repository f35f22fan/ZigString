const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const io = @import("io.zig");
const BitData = @import("bit_data.zig").BitData;
const mtl = @import("mtl.zig");
const Num = @import("Num.zig");

const c = @cImport({
    // See https://github.com/ziglang/zig/issues/515
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
});

const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const String = @import("String.zig").String;
const CaseSensitive = String.CaseSensitive;
const Codepoint = String.Codepoint;
const CodepointSlice = String.CpSlice;
const Context = String.Context;
const CpSlice = String.CpSlice;
const Error = String.Error;
const Index = String.Index;
const KeepEmptyParts = String.KeepEmptyParts;

const DesktopFile = @import("DesktopFile.zig").DesktopFile;
const theme = String.Theme.Dark;

const COLOR_BLUE = "\x1B[34m";
const COLOR_DEFAULT = "\x1B[0m";
const COLOR_GREEN = "\x1B[32m";
const COLOR_RED = "\x1B[0;91m";
const COLOR_YELLOW = "\x1B[93m";
const COLOR_MAGENTA = "\x1B[35m";
const COLOR_CYAN = "\x1B[36m";
const COLOR_BLACK = "\x1B[38;5;16m";
const BLINK_START = "\x1B[5m";
const BLINK_END = "\x1B[25m";
const BOLD_START = "\x1B[1m";
const BOLD_END = "\x1B[0m";
const UNDERLINE_START = "\x1B[4m";
const UNDERLINE_END = "\x1B[0m";

const Truncate = enum(u1) { Yes, No };

var tick: isize = 0;

test "Desktop File" {
    // if (true)
    //     return error.SkipZigTest;

    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    // const home_cstr = try io.getEnv(alloc, io.Folder.Home);
    // defer alloc.free(home_cstr);
    // var fullpath = try String.From(home_cstr);
    // defer fullpath.deinit();
    // try fullpath.append("/Desktop/Firefox.desktop");
    // try fullpath.print(std.debug, "Fullpath: ");
    // var df = try DesktopFile.New(dctx, try fullpath.Clone());
    // defer df.deinit();
    var chromium = try DesktopFile.NewCstr(alloc, "/usr/share/applications/chromium-browser.desktop");
    defer chromium.deinit();

    if (chromium.getName(null)) |value| {
        value.print(@src(), "Name(default): ");
    }

    if (chromium.getName("ru")) |value| {
        value.print(@src(), "Name(ru): ");
    }

    if (chromium.getName("zh_CN")) |value| {
        value.print(@src(), "Name(zh_CN): ");
    }

    if (chromium.getGenericName("zh_CN")) |value| {
        value.print(@src(), "Generic Name(zh_CN): ");
    }

    if (chromium.getComment("zh_CN")) |value| {
        value.print(@src(), "Comment(zh_CN): ");
    }

    if (chromium.getIcon()) |value| {
        value.print(@src(), "Icon: ");
    }

    if (chromium.getActions()) |value| {
        value.print(@src(), "Actions: ");
    }

    if (chromium.getExec()) |value| {
        value.print(@src(), "Exec: ");
    }

    if (chromium.getField("Exec", null, "Desktop Action new-private-window")) |value| {
        value.print(@src(), "Exec(Desktop Action new-private-window): ");
    }

    if (chromium.getMimeTypes()) |value| {
        value.print(@src(), "Mimetypes: ");
    }

    if (chromium.getCategories()) |value| {
        value.print(@src(), "Categories: ");
    }
}

fn readString(in: anytype, correct: []const u8) !void {
    const t1 = getTime();
    const read_str = try String.fromBlob(in);
    defer read_str.deinit();
    const t2 = getTime();
    mtl.debug(@src(), "Done reading binary in {}{s}", .{Num{.value = t2-t1}, TimeExt});
    //read_str.printInfo(@src(), null);
    //try read_str.printCodepoints(@src());
    try expect(read_str.eq(correct));
}

test "Binary read/write string to file" {
    // This test reads/writes the string not in UTF-8,
    // but in its internal binary format.
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();
    {
        //const fp = "/home/fox/size-out.bin";
        const fp = try io.getHome(alloc, "/size-out.bin");
        defer alloc.free(fp);
        var file_out = try std.fs.createFileAbsolute(fp, .{ .truncate = true, .read = true });
        const str1 = "Jos\u{65}\u{301} se fu\u{65}\u{301}";
        const read_path = try io.getHome(alloc, "/Documents/content.xml");
        defer alloc.free(read_path);
        const str2 = try io.readFile(alloc, read_path);
        defer alloc.free(str2);
        const str3 = "Привет";
        const str4 = "违法和不良信息举报电话";
        {
            const s = try String.From(str1);
            defer s.deinit();
            //try s.printCodepoints(@src());
            const memory = try s.toBlob(alloc);
            defer alloc.free(memory);
            try file_out.writeAll(memory);
        }
        {
            const s = try String.From(str2);
            defer s.deinit();
            const memory = try s.toBlob(alloc);
            defer alloc.free(memory);
            try file_out.writeAll(memory);
        }
        {
            const s = try String.From(str3);
            defer s.deinit();
            const memory = try s.toBlob(alloc);
            defer alloc.free(memory);
            try file_out.writeAll(memory);
        }
        {
            const s = try String.From(str4);
            defer s.deinit();
            const memory = try s.toBlob(alloc);
            defer alloc.free(memory);
            try file_out.writeAll(memory);
        }

        file_out.close();

        const file_in = try std.fs.openFileAbsolute(fp, .{});
        defer file_in.close();
        const reader = file_in.reader();
        try readString(&reader, str1);
        try readString(&reader, str2);
        try readString(&reader, str3);
        try readString(&reader, str4);
    }
}

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}