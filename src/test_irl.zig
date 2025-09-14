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

// const c_ = @cImport({
//     // See https://github.com/ziglang/zig/issues/515
//     @cDefine("_NO_CRT_STDIO_INLINE", "1");
//     @cInclude("stdio.h");
// });

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

test "Random Stuff" {
    if (true)
        return error.SkipZigTest;

    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const list = try io.listFilesUtf8(alloc, .Home, "Documents");
    defer {
        for (list.items) |item| {
            mtl.debug(@src(), "{s}", .{item.name});
            item.deinit(alloc);
        }
        list.deinit();
    }
}

test "Desktop File" {
    if (true)
        return error.SkipZigTest;

    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

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

pub fn buildAHref(line: *const String, session_num: String) !String {
    // Generates: <a class="anchor" id="1_0" href="#1_0">1.0</a>
    const anchor = try line.mid(2, -1);
    defer anchor.deinit();
    var nums = ArrayList(String).init(String.ctx.a);
    defer {
        for (nums.items) |item| {
            item.deinit();
        }
        nums.deinit();
    }
    var has_both = false;
    if (anchor.indexOfAscii(".", .{})) |idx| {
        _ = idx;
        has_both = true;
        const pair = try anchor.splitPair(".");
        try nums.append(pair[0]);
        try nums.append(pair[1]);
    } else {
        try nums.append(try session_num.Clone());
        try nums.append(try anchor.Clone());
    }
    
    var a_href = String.New();
    try a_href.addAscii("<a class=\"anchor\" id=\"");
    var sub = try nums.items[0].Clone();
    defer sub.deinit();
    try sub.addChar('_');
    try sub.add(nums.items[1]);
    try a_href.add(sub);
    try a_href.addAscii("\" href=\"#");
    try a_href.add(sub);
    try a_href.addAscii("\">");
    if (has_both) {
        try a_href.add(anchor);
    } else {
        try a_href.add(nums.items[0]);
        try a_href.addAscii(".");
        try a_href.add(nums.items[1]);
    }
    try a_href.addAscii("</a>");
    // mtl.debug(@src(), "{dt}", .{a_href});
    return a_href;
}

const Speaking = enum {
    Ra,
    Questioner,
};

const tloo_path = "/dev/tloo/";
const all_sessions = "<div class=session><a href=\"index.html\">Все сеансы</a></div>";

fn replace(en: *String, idx: Index, bytes: []const u8) !void {
    const en_cloned = try en.Clone();
    defer en_cloned.deinit();
    en.clearAndFree();
    try en.addUtf8(bytes);
    try en.addConsume(try en_cloned.midIndex(idx));
}

fn addEng(to: *String, line: *const String, speaking: ?Speaking) !?Speaking {
    var en = try line.Clone();
    en.trimLeft(); // in case between "-en-" and "RA" there's a space
    var ret_speaking: ?Speaking = speaking;
    if (speaking == null) {
        const ra = "RA";
        const q = "QUESTIONER";
        if (en.startsWithAscii(ra, .{})) {
            ret_speaking = .Ra;
            try replace(&en, .{.cp=ra.len, .gr=ra.len}, "<span class=ra_en>RA:</span>");
        } else if (en.startsWithAscii(q, .{})) {
            ret_speaking = .Questioner;
            try replace(&en, .{.cp=q.len, .gr=q.len}, "<span class=qa_en>QUESTIONER:</span>");
        } else {
        }
    }
    try to.addConsume(en);

    return ret_speaking;
}

fn addRus(to: *String, line: *const String, speaking: ?Speaking) !void {
    var ru = String.New();
    if (speaking) |s| {
        switch (s) {
            .Ra => {
                try ru.addUtf8("<span class=ra_ru>Ра:</span>");
            },
            .Questioner => {
                try ru.addUtf8("<span class=qa_ru>Собеседник:</span>");
            },
        }
    }
    
    try ru.add(line.*);
    try to.addConsume(ru);
}

test "Matrix" {
    if (true)
        return error.SkipZigTest;

    const mat = [_][5]f32{
        [_]f32{ 1.0, 0.0, 0.0, 0.0, 0.0 },
        [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 },
        [_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0 },
        [_]f32{ 0.0, 0.0, 0.0, 1.0, 9.9 },
    };
    //mtl.debug(@src(), "Matrix: {any}", .{mat});
    const stdout = std.io.getStdOut().writer();
    for (mat) |row| {
        for (row) |col| {
            try stdout.print("{d} \n", .{col});
        }
    }

    try stdout.print("\n", .{});
}

test "Translate En to Ru" {
    if (false)
        return error.SkipZigTest;

    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const dirpath = try io.getHomeAscii(alloc, "/dev/tloo/raw/");
    defer dirpath.deinit();
    
    var dir = try io.openDir(dirpath);
    defer dir.close();

    const only_last = true;
    var last_txt_name: ?String = null;

    var filenames = ArrayList(String).init(alloc);
    defer {
        for (filenames.items) |item| {
            item.deinit();
        }

        filenames.deinit();
    }

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        const txt_name = try String.From(entry.name);
        defer txt_name.deinit();
        var html_name = try txt_name.Clone();
        try html_name.changeExtension(".html");
        try filenames.append(html_name);
        if (only_last) {
            if (last_txt_name) |ln| {
                // mtl.debug(@src(), "Skipped {dt}", .{ln});
                ln.deinit();
            }
            last_txt_name = try txt_name.Clone();
        } else {
            try Translate(dirpath, txt_name);
        }
    }

    if (last_txt_name) |fname| {
        try Translate(dirpath, fname);
        fname.deinit();
    }

    // for (filenames.items) |n| {
    //     mtl.debug(@src(), "filename: {dt}", .{n});
    // }

    try CreateHtmlIndex(filenames);
}

fn parseSession(name: String) !String {
    var idx = name.lastIndexOfAscii("_", .{}) orelse return error.Index;
    idx.addOne(); // skipping past "_"
    const idx2 = name.lastIndexOfAscii(".", .{}) orelse return error.Index;

    const number = try name.betweenIndices(idx, idx2);
    var ret = try String.From("Сеанс ");
    try ret.addConsume(number);
    return ret;
}

fn CreateHtmlIndex(filenames: ArrayList(String)) !void {
    var html = String.New();
    defer html.deinit();
    try html.addUtf8(
\\<!DOCTYPE html>
\\<head>
\\  <title>Закон Одного</title>
\\  <meta charset="UTF-8"/>
\\  <link rel="stylesheet" href="styles.css">
\\</head>
\\<body>
\\<div class=session>Книга "Закон Одного" (Материалы Ра)</div>
\\<br><br>
\\<div class=session_date>Список сеансов</div><br>
\\
);

    for (filenames.items) |name| {
        try html.addAscii("<a href=\"");
        try html.add(name);
        const session = try parseSession(name);
        defer session.deinit();
        try html.addAscii("\">");
        try html.add(session);
        try html.addAscii("</a><br>\n");
    }

    try html.addUtf8(
\\ <br><hr/><br>
\\
\\ <span class=book_footnote>Сноски из книги оригинала внесены прямо в текст и имеют такой
\\фон и окраску поскольку это HTML и не делится на страницы, а на сеансы.</span>
\\
\\<p/>
\\<span class=pp>Пояснения переводчика имеют такой фон и окраску.</span>
\\
\\ <br><br><br><br><br>
\\<div style="font-size:12px;">Переводчик и пояснения: Владимир
\\ (f35f22fan AT gmail DOT com)<br>
\\ Перевод доступен на: <a href="https://github.com/f35f22fan/tloo">
\\https://github.com/f35f22fan/tloo</a>
\\<br><br>
\\Чтобы начинающие могли легче и правильнее понять содержимое книги переводчик
\\добавил в содержимое книги свои пояснения, выделенные другим цветом
\\в том числе чтобы те кому это не нужно
\\могли легко это пропускать. Переводчик не претендует что его пояснения являются
\\истиной в последней инстанции, а лишь надеется на их полезность для начинающих.</div>
    );
    try html.addAscii("</body></html>");

    var relative_path = try String.From(tloo_path);
    defer relative_path.deinit();
    try relative_path.addAscii("index.html");

    const save_to_path = try io.getHome(alloc, relative_path);
    defer save_to_path.deinit();

    const utf8 = try save_to_path.toUtf8();
    defer utf8.deinit();

    const out_file = try std.fs.createFileAbsolute(utf8.items, .{});
    defer out_file.close();

    const bytes = try html.toOwnedSlice();
    defer alloc.free(bytes);
    try out_file.writeAll(bytes);
}

fn Translate(dirpath: String, filename: String) !void {
    const txt_fullpath = try String.From2(dirpath, filename);
    defer txt_fullpath.deinit();
    mtl.debug(@src(), "{dt}", .{txt_fullpath});
    const contents_u8 = try io.readFile(alloc, txt_fullpath);
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
    try html.addAscii(
\\<!DOCTYPE html>
\\<head>
\\  <meta charset="UTF-8"/>
\\  <link rel="stylesheet" href="styles.css">
);
    var idx1 = filename.indexOfAscii("_", .{}) orelse return String.Error.Other;
    idx1.addOne();
    const idx2 = filename.indexOfAscii(".", .{}) orelse return String.Error.Other;
    const session_num = try filename.betweenIndices(idx1, idx2);
    defer session_num.deinit();
    try html.addUtf8("\t<title>Сеанс ");
    try html.add(session_num);
    try html.addUtf8(" - Закон Одного</title>\n</head>\n<body><div class=session>Сеанс ");
    try html.add(session_num);
    try html.addAscii("</div>\n<div class=session_date>");
    const date: String = lines.orderedRemove(0);
    try html.addConsume(date);
    try html.addAscii("</div>\n");
    try html.addUtf8(all_sessions);
    
    const anchor_prefix = "__";
    const en_prefix = "-en-";
    const ru_prefix = "-ru-";

    const LastWas = enum {
        en,
        ru,
        anchor
    };

    var last_was: ?LastWas = null;
    var speaking: ?Speaking = null;
    
    for (lines.items) |*line| {
        line.trimLeft();
        if (line.isEmpty()) {
            try html.addAscii("\n<p>\n");
            continue;
        }
        
        if (line.startsWithAscii(anchor_prefix, .{})) {
            speaking = null;
            if (last_was != null) {
                try html.addAscii("</td>\n\t</tr>\n</table>");
            }
            last_was = .anchor;
            try html.addAscii("\n<table>\n\t<tr>\n\t\t<td>");
            try html.addConsume(try buildAHref(line, session_num));
            try html.addAscii("</td>");
        } else if (line.startsWithAscii(en_prefix, .{})) {
            var was_anchor = false;
            if (last_was) |lastwas| {
                if (lastwas == .ru) {
                    try html.addAscii("</td>\n\t</tr>");
                } else if (lastwas == .anchor) {
                    was_anchor = true;
                    try html.addAscii("\n\t\t<td class=\"eng\">");        
                }
            }
            last_was = .en;
            if (!was_anchor) {
                try html.addAscii("\n\t<tr>\n\t\t<td></td>\n\t\t<td class=\"eng\">");
            }
            
            const en = try line.mid(4, -1);
            defer en.deinit();
            speaking = try addEng(&html, &en, speaking);
        } else if (line.startsWithAscii(ru_prefix, .{})) {
            last_was = .ru;
            try html.addAscii("</td>\n\t</tr>\n\t<tr>\n\t\t<td></td>\n\t\t<td class=\"rus\">");
            const ru = try line.mid(4, -1);
            defer ru.deinit();
            try addRus(&html, &ru, speaking);
            speaking = null;
        } else if (last_was) |lw| {
            if (lw == .en) {
                try html.addChar('\n');
                speaking = try addEng(&html, line, speaking);
            } else if (lw == .ru) {
                try html.addChar('\n');
                try addRus(&html, line, null);
                speaking = null;
            }
        }
    }

    try html.addAscii("</td>\n\t</tr>\n</table>\n\n");
    try html.addAscii("<br><br><br>");
    try html.addUtf8(all_sessions);
    try html.addAscii("</body></html>");

    var html_fn = try filename.Clone();
    try html_fn.changeExtension(".html");
    defer html_fn.deinit();
    const relative_path = try String.Concat(tloo_path, html_fn);
    defer relative_path.deinit();

    const save_to_path = try io.getHome(alloc, relative_path);
    defer save_to_path.deinit();

    const utf8 = try save_to_path.toUtf8();
    defer utf8.deinit();

    const out_file = try std.fs.createFileAbsolute(utf8.items, .{});
    defer out_file.close();

    const bytes = try html.toOwnedSlice();
    defer alloc.free(bytes);
    try out_file.writeAll(bytes);
}