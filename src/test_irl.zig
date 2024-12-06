const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const io = @import("io.zig");

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

const Truncate = enum(u1) {
    Yes,
    No
};

fn ticker(step: u8) !void {
    _ = step;
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();   
    var s = try String.From("Hello, World!");
    try s.append("...From another thread");
    defer s.deinit();
    std.debug.print("{s}():==================== {}\n", .{@src().fn_name, s});
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
        try value.print(std.debug, "Name(default): ");
    }

    if (chromium.getName("ru")) |value| {
        try value.print(std.debug, "Name(ru): ");
    }

    if (chromium.getName("zh_CN")) |value| {
        try value.print(std.debug, "Name(zh_CN): ");
    }

    if (chromium.getGenericName("zh_CN")) |value| {
        try value.print(std.debug, "Generic Name(zh_CN): ");
    }

    if (chromium.getComment("zh_CN")) |value| {
        try value.print(std.debug, "Comment(zh_CN): ");
    }

    if (chromium.getIcon()) |value| {
        try value.print(std.debug, "Icon: ");
    }

    if (chromium.getActions()) |value| {
        try value.print(std.debug, "Actions: ");
    }

    if (chromium.getExec()) |value| {
        try value.print(std.debug, "Exec: ");
    }

    if (chromium.getField("Exec", null, "Desktop Action new-private-window")) |value| {
        try value.print(std.debug, "Exec(Desktop Action new-private-window): ");
    }

    if (chromium.getMimeTypes()) |value| {
        try value.print(std.debug, "Mimetypes: ");
    }

    if (chromium.getCategories()) |value| {
        try value.print(std.debug, "Categories: ");
    }
}

fn writeString(input_str: []const u8, writer: anytype, flush: String.Flush) !void {
    const s = try String.From(input_str);
    defer s.deinit();
    try s.printGraphemes(std.debug, theme);
    try s.printCodepoints(std.debug, theme);
    try s.writeTo(writer, flush);

    // var m = [_]u8{0} ** 256;
    // var stream = std.io.fixedBufferStream(&m);
    // try s.writeTo(stream.writer());

    // for (m) |k| {
    //     std.debug.print("{X}| ", .{k});
    // }
}

fn readString(reader: anytype) !void {
    const read_str = try String.readFrom(reader);
    defer read_str.deinit();
    //try expect(read_str.eq(input));
    try read_str.printInfo(std.debug, "Read str: ");
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
    //try fullpath.print(std.debug, null);
    const fp = try fullpath.toString();
    defer fp.deinit();

    const file = try std.fs.createFileAbsolute(fp.items, .{.truncate = true, .read = true});
    var writer = file.writer();
    var bitw = std.io.bitWriter(.big, &writer);
    try writeString("Jos\u{65}\u{301} se fu\u{65}\u{301}",
    &bitw, String.Flush.No);
    try writeString("Hello", &bitw, String.Flush.Yes);
    file.close();

    const file_in = try std.fs.openFileAbsolute(fp.items, .{});
    defer file_in.close();

    var reader = file_in.reader();
    var bits = std.io.bitReader(.big, &reader);
    try readString(&bits);
    try readString(&bits);
}