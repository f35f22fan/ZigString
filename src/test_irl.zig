const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const io = @import("io.zig");
const mtl = @import("mtl.zig");

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

fn ticker(step: u8) !void {
    _ = step;
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();
    var s = try String.From("Hello, World!");
    try s.append("...From another thread");
    defer s.deinit();
    std.debug.print("{s}():==================== {}\n", .{ @src().fn_name, s });
    // while (true) {
    //     std.time.sleep(1 * std.time.ns_per_s);
    //     tick += @as(isize, step);
    // }
}

var tick: isize = 0;

test "Desktop File" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    // const thread = try std.Thread.spawn(.{}, ticker, .{@as(u8, 1)});
    // thread.join();

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
        try value.print(@src(), "Name(default): ");
    }

    if (chromium.getName("ru")) |value| {
        try value.print(@src(), "Name(ru): ");
    }

    if (chromium.getName("zh_CN")) |value| {
        try value.print(@src(), "Name(zh_CN): ");
    }

    if (chromium.getGenericName("zh_CN")) |value| {
        try value.print(@src(), "Generic Name(zh_CN): ");
    }

    if (chromium.getComment("zh_CN")) |value| {
        try value.print(@src(), "Comment(zh_CN): ");
    }

    if (chromium.getIcon()) |value| {
        try value.print(@src(), "Icon: ");
    }

    if (chromium.getActions()) |value| {
        try value.print(@src(), "Actions: ");
    }

    if (chromium.getExec()) |value| {
        try value.print(@src(), "Exec: ");
    }

    if (chromium.getField("Exec", null, "Desktop Action new-private-window")) |value| {
        try value.print(@src(), "Exec(Desktop Action new-private-window): ");
    }

    if (chromium.getMimeTypes()) |value| {
        try value.print(@src(), "Mimetypes: ");
    }

    if (chromium.getCategories()) |value| {
        try value.print(@src(), "Categories: ");
    }
}

fn writeString(input_str: []const u8, writer: anytype, flush: String.Flush) !void {
    const s = try String.From(input_str);
    defer s.deinit();
    try s.printGraphemes(@src());
    try s.printCodepoints(@src());
    try s.writeTo(writer, flush);

    // var m = [_]u8{0} ** 256;
    // var stream = std.io.fixedBufferStream(&m);
    // try s.writeTo(stream.writer());

    // for (m) |k| {
    //     std.debug.print("{X}| ", .{k});
    // }
}

fn readString(reader: anytype, correct: []const u8) !void {
    const read_str = try String.readFrom(reader);
    defer read_str.deinit();
    try expect(read_str.eq(correct));
    //try read_str.printInfo(@src(), "Read str: ");
}

test "Binary read/write string to file" {
    // This test reads/writes the string not in UTF-8,
    // but in its internal binary format.
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const home_cstr = try io.getEnv(alloc, io.Folder.Home);
    defer alloc.free(home_cstr);
    var fullpath = try String.From(home_cstr);
    defer fullpath.deinit();
    try fullpath.append("/out.txt");
    //try fullpath.print(@src(), "Filepath: ");
    const fp = try fullpath.toString();
    defer fp.deinit();

    const str1 = "Jos\u{65}\u{301} se fu\u{65}\u{301}";
    const str2 = "Hello";
    const str3 = "Добрый день";
    {
        const file_out = try std.fs.createFileAbsolute(fp.items, .{ .truncate = true, .read = true });
        defer file_out.close();
        var bitw = std.io.bitWriter(.big, file_out.writer());
        // When writing multiple strings in a row only the last write should
        // equal=Flush.Yes because it flushes extra empty bits to
        // fill the last byte.
        try writeString(str1, &bitw, String.Flush.No);
        try writeString(str2, &bitw, String.Flush.No);
        try writeString(str3, &bitw, String.Flush.Yes);
    }

    const file_in = try std.fs.openFileAbsolute(fp.items, .{});
    defer file_in.close();

    var bits = std.io.bitReader(.big, file_in.reader());
    try readString(&bits, str1);
    try readString(&bits, str2);
    try readString(&bits, str3);
}
