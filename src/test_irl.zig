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
const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const String = @import("String.zig").String;
const Slice = String.Slice;
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

test "Desktop File" {
    if (true)
        return error.SkipZigTest;

    try String.Init(alloc);
    defer String.Deinit();

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

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

pub fn buildAHref(numbers_str: *Slice, session_num: String) !String {
    // Generates: <a class="anchor" id="1_0" href="#1_0">1.0</a>
    numbers_str.shrinkRaw(2, .Left); // 2 is length of "__"
    var nums: ArrayList(String) = .empty;
    defer {
        for (nums.items) |item| {
            item.deinit();
        }
        nums.deinit(alloc);
    }
    var has_both = false;
    if (numbers_str.indexOfAscii(".", .{})) |idx| {
        has_both = true;
        const pair = try numbers_str.splitPairAt(idx, null);
        try nums.append(alloc, try pair[0].toString());
        try nums.append(alloc, try pair[1].toString());
    } else {
        try nums.append(alloc, session_num);
        try nums.append(alloc, try numbers_str.toString());
    }

    var a_href = try String.NewAscii("<a class=\"anchor\" id=\"");
    var sub = try nums.items[0].Clone();
    try sub.addChar('_');
    try sub.add(nums.items[1]);
    try a_href.add(sub);
    try a_href.addAscii("\" href=\"#");
    try a_href.addConsume(sub);
    try a_href.addAscii("\">");
    if (has_both) {
        try a_href.addSlice(numbers_str.*);
    } else {
        try a_href.add(nums.items[0]);
        try a_href.addChar('.');
        try a_href.add(nums.items[1]);
    }
    try a_href.addAscii("</a>");

    return a_href;
}

const Speaking = enum {
    Ra,
    Questioner,
    Jim,
};

const tloo_path = "/dev/tloo/";
const all_sessions = "<div class=session><a href=\"index.html\">Все сеансы</a></div>";

fn replace(line: *const Slice, offset: usize, bytes: []const u8) !String {
    var ret = try String.New(bytes);
    const slice_start = line.start.plusN(offset);
    try ret.addSlice(line.mid(slice_start));
    return ret;
}

fn addEng(to: *String, line: *Slice, speaking: ?Speaking) !?Speaking {
    line.trimLeft(); // in case between "-en-" and "RA" there's a space
    var ret_speaking: ?Speaking = speaking;
    var added = false;
    if (speaking == null) {
        const ra = "RA";
        const q = "QUESTIONER";
        const jim = "JIM";
        if (line.startsWithAscii(ra, .{})) {
            added = true;
            ret_speaking = .Ra;
            try to.addConsume(try replace(line, ra.len, "<span class=ra_en>RA:</span>"));
        } else if (line.startsWithAscii(q, .{})) {
            added = true;
            ret_speaking = .Questioner;
            try to.addConsume(try replace(line, q.len, "<span class=qa_en>QUESTIONER:</span>"));
        } else if (line.startsWithAscii(jim, .{})) {
            added = true;
            ret_speaking = .Jim;
            try to.addConsume(try replace(line, jim.len, "<span class=qa_en>JIM:</span>"));
        }
    }
    
    if (!added) {
        try to.addSlice(line.*);
    }

    return ret_speaking;
}

fn addRus(to: *String, line: Slice, speaking: ?Speaking) !void {
    var ru = String.Empty();
    if (speaking) |s| switch(s) {
        .Ra => {
            try ru.addUtf8("<span class=ra_ru>Ра:</span>");
        },
        .Questioner => {
            try ru.addUtf8("<span class=qa_ru>Собеседник:</span>");
        },
        .Jim => {
            try ru.addUtf8("<span class=qa_ru>Джим:</span>");
        },
    };

    try ru.addSlice(line);
    try to.addConsume(ru);
}

test "Translate En to Ru" {
    if (false)
        return error.SkipZigTest;

    try String.Init(alloc);
    defer String.Deinit();

    const dirpath = try io.getHomeAscii(alloc, "/dev/tloo/raw/");
    defer dirpath.deinit();

    var dir = try io.openDir(alloc, dirpath);
    defer dir.close();

    const only_last = true;
    var last_txt_name: ?String = null;

    if (false) {
        const name = try String.NewAscii("session_46.txt");
        defer name.deinit();
        try Translate(dirpath, name);
        return;
    }

    var filenames: ArrayList(String) = .empty;
    defer {
        for (filenames.items) |item| {
            item.deinit();
        }

        filenames.deinit(alloc);
    }

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        var txt_name = try String.New(entry.name);
        defer txt_name.deinit();
        var html_name = try txt_name.Clone();
        try html_name.changeToAsciiExtension(".html");
        try filenames.append(alloc, html_name);
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

    const number = name.slice(idx, idx2);
    var ret = try String.New("Сеанс ");
    try ret.addSlice(number);
    return ret;
}

fn CreateHtmlIndex(filenames: ArrayList(String)) !void {
    var html = String.Empty();
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

    var relative_path = try String.New(tloo_path);
    defer relative_path.deinit();
    try relative_path.addAscii("index.html");

    const save_to_path = try io.getHome(alloc, relative_path);
    defer save_to_path.deinit();

    var utf8 = try save_to_path.toUtf8(alloc);
    defer utf8.deinit(alloc);

    const out_file = try std.fs.createFileAbsolute(utf8.items, .{});
    defer out_file.close();

    var byte_buf = try html.toUtf8(alloc);
    defer byte_buf.deinit(alloc);
    try out_file.writeAll(byte_buf.items);
}

fn Translate(dirpath: String, filename: String) !void {
    const txt_fullpath = try dirpath.CloneWith(filename);
    defer txt_fullpath.deinit();
    mtl.debug(@src(), "{f}", .{txt_fullpath});
    var contents_u8 = try io.readFile(alloc, txt_fullpath);
    defer contents_u8.deinit(alloc);

    var contents = try String.New(contents_u8.items[0..]);
    defer contents.deinit();

    var lines = try contents.splitSlices("\n", .{});
    defer {
        lines.deinit(alloc);
    }

    if (lines.items.len <= 2) {
        return;
    }

    var html = String.Empty();
    defer html.deinit();
    try html.addAscii(
        \\<!DOCTYPE html>
        \\<head>
        \\  <meta charset="UTF-8"/>
        \\  <link rel="stylesheet" href="styles.css">
    );
    var idx1 = filename.indexOfAscii("_", .{}) orelse return error.Other;
    idx1.addOne();
    const idx2 = filename.indexOfAscii(".", .{}) orelse return error.Other;
    const session_num = filename.slice(idx1, idx2);
    try html.addUtf8("\t<title>Сеанс ");
    try html.addSlice(session_num);
    try html.addUtf8(" - Закон Одного</title>\n</head>\n<body><div class=session>Сеанс ");
    try html.addSlice(session_num);
    try html.addAscii("</div>\n<div class=session_date>");
    const date = lines.orderedRemove(0);
    try html.addSlice(date);
    try html.addAscii("</div>\n");
    try html.addUtf8(all_sessions);

    const new_question_prefix = "__";
    const en_prefix = "-en-";
    const ru_prefix = "-ru-";

    const LastWas = enum { en, ru, anchor };

    var last_was: ?LastWas = null;
    var who_speaks: ?Speaking = null;

    for (lines.items) |*line| {
        line.trimLeft();
        if (line.isEmpty()) {
            try html.addAscii("\n<p>\n");
            continue;
        }

        if (line.startsWithAscii(new_question_prefix, .{})) {
            who_speaks = null;
            if (last_was != null) {
                try html.addAscii("</td>\n\t</tr>\n</table>");
            }
            last_was = .anchor;
            try html.addAscii("\n<table>\n\t<tr>\n\t\t<td>");
            // mtl.debug(@src(), "{f}, {f}", .{line._(2), session_num._(2)});
            try html.addConsume(try buildAHref(line, try session_num.toString()));
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

            const from: Index = line.start.plusN(en_prefix.len);
            var en = line.mid(from);
            who_speaks = try addEng(&html, &en, who_speaks);
        } else if (line.startsWithAscii(ru_prefix, .{})) {
            last_was = .ru;
            try html.addAscii("</td>\n\t</tr>\n\t<tr>\n\t\t<td></td>\n\t\t<td class=\"rus\">");
            const from: Index = line.start.plusN(ru_prefix.len);
            const ru = line.mid(from);
            try addRus(&html, ru, who_speaks);
            who_speaks = null;
        } else if (last_was) |lw| {
            if (lw == .en) {
                try html.addChar('\n');
                who_speaks = try addEng(&html, line, who_speaks);
            } else if (lw == .ru) {
                try html.addChar('\n');
                try addRus(&html, line.*, null);
                who_speaks = null;
            }
        }
    }

    try html.addAscii("</td>\n\t</tr>\n</table>\n\n");
    try html.addAscii("<br><br><br>");
    try html.addUtf8(all_sessions);
    try html.addAscii("</body></html>");

    var html_filename = try filename.Clone();
    try html_filename.changeToAsciiExtension(".html");
    var relative_path = try String.New(tloo_path);
    defer relative_path.deinit();
    try relative_path.addConsume(html_filename);

    const save_to_path = try io.getHome(alloc, relative_path);
    defer save_to_path.deinit();

    var utf8 = try save_to_path.toUtf8(alloc);
    defer utf8.deinit(alloc);

    const out_file = try std.fs.createFileAbsolute(utf8.items, .{});
    defer out_file.close();

    var byte_buf = try html.toUtf8(alloc);
    defer byte_buf.deinit(alloc);

    try out_file.writeAll(byte_buf.items);
}
