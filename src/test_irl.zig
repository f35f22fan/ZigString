const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const alloc = std.testing.allocator;

const io = @import("io.zig");
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
    if (true)
        return error.SkipZigTest;

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

fn writeString(input_str: []const u8, file_out: *std.fs.File, fp: []const u8) !void {
    _ = fp;
    // const ts1 = getTime();
    const str_out = try String.From(input_str);
    defer str_out.deinit();
    // const ts2 = getTime();
    // mtl.debug(@src(), "String.From(cstr) done in {}{s}", .{Num{.value=ts2-ts1}, TimeExt});
    try str_out.printInfo(@src(), null);
    //const t1 = getTime();
    const str_byte_count = str_out.computeSizeInBytes();
    mtl.debug(@src(), "str_byte_count: {}", .{Num.New(str_byte_count)});
    const memory = try alloc.alloc(u8, str_byte_count);
    defer alloc.free(memory);
    var stream = std.io.fixedBufferStream(memory);
    var bits = std.io.bitWriter(.big, stream.writer());
    // mtl.debug(@src(), "bitw type info: {}", .{@TypeOf(&bitw)});
    try str_out.writeTo(&bits);
    try file_out.writeAll(memory);
    //const t2 = getTime();
    //mtl.debug(@src(), "Done Writing in {}{s} to {s}", .{Num{.value=t2-t1}, TimeExt, fp});
}

fn readString(in: anytype, correct: []const u8) !void {
    //const t1 = getTime();
    const read_str = try String.readFrom(in);
    defer read_str.deinit();
    //const t2 = getTime();
    //mtl.debug(@src(), "Done reading binary in {}{s}", .{Num{.value = t2-t1}, TimeExt});
    try read_str.printInfo(@src(), null);
    
    // const buf = try read_str.toString();
    // defer buf.deinit();
    // const out_path = "/home/fox/compare.xml";
    // const compare_file = try std.fs.createFileAbsolute(out_path, .{.truncate=true, .read=true});
    // defer compare_file.close();
    // try compare_file.writeAll(buf.items);

    try expect(read_str.eq(correct));
}

test "Binary read/write string to file" {
    // This test reads/writes the string not in UTF-8,
    // but in its internal binary format.
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    // const home_cstr = try io.getEnv(alloc, io.Folder.Home);
    // defer alloc.free(home_cstr);
    {
        const fp = "/home/fox/size-out.bin";
        var file_out = try std.fs.createFileAbsolute(fp, .{ .truncate = true, .read = true });
        
        const str1 = "Jos\u{65}\u{301} se fu\u{65}\u{301}";
        try writeString(str1, &file_out, fp);

        const str2 = try io.readFile(alloc, "/home/fox/Documents/content.xml");
        defer alloc.free(str2);
        try writeString(str2, &file_out, fp);

        const str3 = "Привет";
        try writeString(str3, &file_out, fp);
        
        file_out.close();

        const file_in = try std.fs.openFileAbsolute(fp, .{});
        var bits = std.io.bitReader(.big, file_in.reader());
        mtl.separator(@src(), "1");
        try readString(&bits, str1);
        mtl.separator(@src(), "2");
        try readString(&bits, str2);
        mtl.separator(@src(), "3");
        try readString(&bits, str3);
        file_in.close();
    }
}

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}