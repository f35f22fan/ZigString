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
    if (true)
        return error.SkipZigTest;

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
    mtl.debug(@src(), "Done reading binary in {}{s}", .{ Num{ .value = t2 - t1 }, TimeExt });
    //read_str.printInfo(@src(), null);
    //try read_str.printCodepoints(@src());
    try expect(read_str.eqBytes(correct));
}

test "Binary read/write string to file" {
    if (true)
         return error.SkipZigTest;
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

pub fn buildAHref(line: *const String) !String {
    const anchor = try line.mid(2, -1);
    defer anchor.deinit();
    const nums = try anchor.splitPair(".");
    // <a class="anchor" id="1_0" href="#1_0">1.0</a>
    var a_href = String.New();
    try a_href.addBytes("<a class=\"anchor\" id=\"");
    var sub = nums[0];
    defer sub.deinit();
    try sub.addBytes("_");
    try sub.addConsume(nums[1]);
    try a_href.add(sub);
    try a_href.addBytes("\" href=\"#");
    try a_href.add(sub);
    try a_href.addBytes("\">");
    try a_href.add(anchor);
    try a_href.addBytes("</a>");
    // mtl.debug(@src(), "{dt}", .{a_href});
    return a_href;
}

const Speaking = enum {
    Ra,
    Questioner,
};

fn replace(en: *String, idx: Index, bytes: []const u8) !void {
    const en_cloned = try en.Clone();
    defer en_cloned.deinit();
    en.clearAndFree();
    try en.addBytes(bytes);
    try en.addConsume(try en_cloned.midIndex(idx));
}

fn addEng(to: *String, line: *const String, skip_prefix: bool) !?Speaking {
    const skip_num: usize = if (skip_prefix) 4 else 0;

    if (line.size() <= skip_num) {
        mtl.debug(@src(), "Warning: line is empty", .{});
        return null;
    }

    var en = try line.mid(skip_num, -1);
    var speaking: ?Speaking = null;
    if (skip_prefix) {
        try en.trimLeft(); // in case between "-en-" and "RA" there's a space
        if (en.startsWithBytes("RA", .{})) {
            speaking = .Ra;
            try replace(&en, .{.cp=2, .gr=2}, "<span class=ra_en>RA:</span>");
        } else if (en.startsWithBytes("QUESTIONER", .{})) {
            speaking = .Questioner;
            try replace(&en, .{.cp=10, .gr=10}, "<span class=qa_en>QUESTIONER:</span>");
        }
    }
    try to.addConsume(en);

    return speaking;
}

fn addRus(to: *String, line: *const String, skip_prefix: bool, speaking: ?Speaking) !void {
    const skip_num: usize = if (skip_prefix) 4 else 0;
    var ru = String.New();
    if (speaking) |s| {
        switch (s) {
            .Ra => {
                try ru.addBytes("<span class=ra_ru>Ра:</span>");
            },
            .Questioner => {
                try ru.addBytes("<span class=qa_ru>Собеседник:</span>");
            },
        }
    }
    
    if (line.size() <= skip_num) {
        mtl.debug(@src(), "Warning: line is empty", .{});
        return; // empty
    }
    // mtl.debug(@src(), "{dt}, skip_num: {}", .{line, skip_num});
    var l = try line.mid(skip_num, -1);
    try l.trimLeft();
    try ru.addConsume(l);
    try to.addConsume(ru);
}


test "Translate En to Ru" {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const dirpath = try io.getHome(alloc, "/dev/tloo/raw/");
    defer alloc.free(dirpath);
    
    var dir = try io.openDirBytes(dirpath);
    defer dir.close();

    const only_last = true;
    var last_name = String.New();
    defer last_name.deinit();

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        if (only_last) {
            last_name.clearRetainingCapacity();
            try last_name.addBytes(entry.name);
        } else {
            try Translate(dirpath, entry.name);
        }
    }

    if (only_last) {
        try Translate(dirpath, last_name);
    }
}


fn Translate(dirpath: []const u8, filename: String) !void {
    const txt_session_path = try String.Concat(dirpath, filename);
    defer txt_session_path.deinit();
    mtl.debug(@src(), "path:\"{s}\"", .{txt_session_path.items});
    const contents_u8 = try io.readFile(alloc, txt_session_path.items);
    defer alloc.free(contents_u8);

    const contents = try String.From(contents_u8);
    defer contents.deinit();

    var lines = try contents.split("\n", .{});
    defer {
        for (lines.items) |line| {
            line.deinit();
        }
        lines.deinit();
    }

    var html = String.New();
    defer html.deinit();
    try html.addBytes(
\\<html>
\\<head>
\\  <meta charset="UTF-8"/>
\\  <link rel="stylesheet" href="styles.css">
);
    var idx1 = filename.indexOfBytes("_", .{}) orelse return String.Error.Other;
    idx1.addOne();
    const idx2 = filename.indexOfBytes(".", .{}) orelse return String.Error.Other;
    const session_num = try filename.betweenIndices(idx1, idx2);
    defer session_num.deinit();
    try html.addBytes("\t<title>Сеанс ");
    try html.add(session_num);
    try html.addBytes(" - Закон Одного</title>\n</head>\n<body><div class=session>Сеанс ");
    try html.add(session_num);
    try html.addBytes("</div>\n<div class=session_date>");
    const date: String = lines.orderedRemove(0);
    try html.addConsume(date);
    try html.addBytes("</div>\n");

    
    const anchor_prefix = try String.From("__");
    defer anchor_prefix.deinit();
    const en_prefix = try String.From("-en-");
    defer en_prefix.deinit();
    const ru_prefix = try String.From("-ru-");
    defer ru_prefix.deinit();

    const LastWas = enum {
        en,
        ru,
        anchor
    };

    var last_was: ?LastWas = null;
    var speaking: ?Speaking = null;

    for (lines.items) |*line| {
        try line.trimLeft();
        if (line.isEmpty()) {
            try html.addBytes("\n<p/>\n");
            continue;
        }
        
        if (line.startsWith(anchor_prefix, .{})) {
            if (last_was != null) {
                try html.addBytes("</td>\n\t</tr>\n</table>");
            }
            last_was = .anchor;
            try html.addBytes("\n<table>\n\t<tr>\n\t\t<td>");
            try html.addConsume(try buildAHref(line));
            try html.addBytes("</td>");
        } else if (line.startsWith(en_prefix, .{})) {
            var was_anchor = false;
            if (last_was) |lw| {
                if (lw == .ru) {
                    try html.addBytes("</td>\n\t</tr>");
                } else if (lw == .anchor) {
                    was_anchor = true;
                    try html.addBytes("\n\t\t<td class=\"eng\">");        
                }
            }
            last_was = .en;
            if (!was_anchor) {
                try html.addBytes("\n\t<tr>\n\t\t<td></td>\n\t\t<td class=\"eng\">");
            }
            speaking = try addEng(&html, line, true);
        } else if (line.startsWith(ru_prefix, .{})) {
            last_was = .ru;
            try html.addBytes("</td>\n\t</tr>\n\t<tr>\n\t\t<td></td>\n\t\t<td class=\"rus\">");
            try addRus(&html, line, true, speaking);
        } else if (last_was) |lw| {
            if (lw == .en) {
                try html.addBytes("\n");
                _ = try addEng(&html, line, false);
            } else if (lw == .ru) {
                try html.addBytes("\n");
                try addRus(&html, line, false, null);
            }
        }
    }

    try html.addBytes("</td>\n\t</tr>\n</table>\n\n</html>");
    const bytes = try html.toOwnedSlice();
    defer alloc.free(bytes);

    const out_name = try io.changeExtension(filename, ".html");
    defer out_name.deinit();
    const relative_path = try String.Concat("/dev/tloo/", out_name);
    defer relative_path.deinit();

    const save_to_path = try io.getHome(alloc, relative_path.items);
    defer alloc.free(save_to_path);

    const out_file = try std.fs.createFileAbsolute(save_to_path, .{});
    defer out_file.close();
    try out_file.writeAll(bytes);
}