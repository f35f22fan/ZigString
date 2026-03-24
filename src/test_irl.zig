const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
// const alloc = std.testing.allocator;

const io = @import("io.zig");
const BitData = @import("bit_data.zig").BitData;
const mtl = @import("mtl.zig");
const Num = @import("Num.zig");
const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const Ctring = @import("Ctring.zig").Ctring;
const View = Ctring.View;
const DesktopFile = @import("DesktopFile.zig").DesktopFile;

test "Desktop File" {
    if (true)
        return error.SkipZigTest;

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer if (gpa.deinit() == .leak) std.process.exit(1);
    // const alloc = gpa.allocator();
    const alloc = std.testing.allocator;
       
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

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

pub fn buildAHref(alloc: Allocator, numbers_str: *View, session_num: Ctring) !Ctring {
    // Generates: <a class="anchor" id="1_0" href="#1_0">1.0</a>
    numbers_str.moveBy(2, .Left); // 2 is length of "__"
    var nums: ArrayList(Ctring) = .empty;
    defer {
        for (nums.items) |*item| {
            item.deinit();
        }
        nums.deinit(alloc);
    }
    var has_both = false;
    if (numbers_str.findAscii(".", null)) |idx| {
        has_both = true;
        const pair = try numbers_str.splitPairAt(idx, 1);
        try nums.append(alloc, try pair[0].toString());
        try nums.append(alloc, try pair[1].toString());
    } else {
        try nums.append(alloc, session_num);
        try nums.append(alloc, try numbers_str.toString());
    }

    var a_href = try Ctring.Ascii("<a class=\"anchor\" id=\"");
    var sub = try nums.items[0].clone(.{});
    defer sub.deinit();
    try sub.addChar('_');
    try sub.add(nums.items[1]);
    try a_href.add(sub);
    try a_href.addAscii("\" href=\"#");
    try a_href.add(sub);
    try a_href.addAscii("\">");
    if (has_both) {
        try a_href.addView(numbers_str.*);
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

fn replace(line: *const View, offset: usize, bytes: []const u8) !Ctring {
    var ret = try Ctring.New(bytes);
    const slice_start = line.start + offset;
    try ret.addView(line.mid(slice_start));
    return ret;
}

fn addEng(to: *Ctring, line: *View, speaking: ?Speaking) !?Speaking {
    line.trimLeft(); // in case between "-en-" and "RA" there's a space
    var ret_speaking: ?Speaking = speaking;
    var added = false;
    if (speaking == null) {
        const ra = "RA";
        const q = "QUESTIONER";
        const jim = "JIM";
        // mtl.debug(@src(), "line: \"{f}\": {}-{}", .{line._(2), line.start, line.end});
        if (line.startsWithAscii(ra)) {
            added = true;
            ret_speaking = .Ra;
            var sr = try replace(line, ra.len, "<span class=ra_en>RA:</span>");
            defer sr.deinit();
            try to.add(sr);
        } else if (line.startsWithAscii(q)) {
            added = true;
            ret_speaking = .Questioner;
            var sr = try replace(line, q.len, "<span class=qa_en>QUESTIONER:</span>");
            defer sr.deinit();
            try to.add(sr);
        } else if (line.startsWithAscii(jim)) {
            added = true;
            ret_speaking = .Jim;
            var sr = try replace(line, jim.len, "<span class=qa_en>JIM:</span>");
            defer sr.deinit();
            try to.add(sr);
        }
    }
    
    if (!added) {
        try to.addView(line.*);
    }

    return ret_speaking;
}

fn addRus(to: *Ctring, line: View, speaking: ?Speaking) !void {
    var ru = Ctring.Empty();
    defer ru.deinit();
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

    try ru.addView(line);
    try to.add(ru);
}

test "Translate En to Ru" {
    if (false)
        return error.SkipZigTest;

    const alloc = std.testing.allocator;

    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    var dirpath = try io.getHomeAscii2(alloc, "/dev/tloo/raw/");
    defer dirpath.deinit();
    // mtl.debug(@src(), "{f}", .{dirpath._(2)});

    var dir = try io.openDir2(alloc, dirpath);
    defer dir.close();

    const only_last = true;
    var last_txt_name: ?Ctring = null;

    if (false) {
        var name = try Ctring.Ascii("session_46.txt");
        defer name.deinit();
        try Translate(alloc, dirpath, name);
        return;
    }

    var filenames: ArrayList(Ctring) = .empty;
    defer {
        for (filenames.items) |*item| {
            item.deinit();
        }

        filenames.deinit(alloc);
    }

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        var txt_name = try Ctring.New(entry.name);
        defer txt_name.deinit();
        var html_name = try txt_name.clone(.{});
        try html_name.changeToAsciiExtension(".html");
        try filenames.append(alloc, html_name);
        if (only_last) {
            if (last_txt_name) |*ln| {
                // mtl.debug(@src(), "Skipped {dt}", .{ln});
                ln.deinit();
            }
            last_txt_name = try txt_name.clone(.{});
        } else {
            try Translate(alloc, dirpath, txt_name);
        }
    }

    if (last_txt_name) |*fname| {
        try Translate(alloc, dirpath, fname.*);
        fname.deinit();
    }

    try CreateHtmlIndex(alloc, filenames);
}

fn parseSession(name: Ctring) !Ctring {
    var idx = name.lastIndexOfAscii("_", .{}) orelse return error.Index;
    idx += 1; // skipping past "_"
    const idx2 = name.lastIndexOfAscii(".", .{}) orelse return error.Index;

    const number = name.view(idx, idx2);
    var ret = try Ctring.New("Сеанс ");
    try ret.addView(number);
    return ret;
}

fn CreateHtmlIndex(alloc: Allocator, filenames: ArrayList(Ctring)) !void {
    var html = Ctring.Empty();
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
        var session = try parseSession(name);
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

    var relative_path = try Ctring.New(tloo_path);
    defer relative_path.deinit();
    try relative_path.addAscii("index.html");

    var save_to_path = try io.getHome2(alloc, relative_path);
    defer save_to_path.deinit();

    var utf8 = try save_to_path.toBytes(alloc, .{});
    defer utf8.deinit(alloc);

    const out_file = try std.fs.createFileAbsolute(utf8.items, .{});
    defer out_file.close();

    var byte_buf = try html.toBytes(alloc, .{});
    defer byte_buf.deinit(alloc);
    try out_file.writeAll(byte_buf.items);
}

fn Translate(alloc: Allocator, dirpath: Ctring, filename: Ctring) !void {
    var txt_fullpath = try dirpath.clone(.{});
    try txt_fullpath.add(filename);
    defer txt_fullpath.deinit();
    mtl.debug(@src(), "{f}", .{txt_fullpath});
    var contents_u8 = try io.readFile2(alloc, txt_fullpath);
    defer contents_u8.deinit(alloc);
    var contents = try Ctring.New(contents_u8.items[0..]);
    defer contents.deinit();

    const cview = contents.view(0, contents.afterLast());
    var lines = try cview.splitAscii("\n", true);
    defer lines.deinit(alloc);
    if (lines.items.len <= 2) {
        return;
    }

    var html = try Ctring.Ascii(
        \\<!DOCTYPE html>
        \\<head>
        \\  <meta charset="UTF-8"/>
        \\  <link rel="stylesheet" href="styles.css">
    );
    defer html.deinit();
    var idx1 = filename.findAscii("_", .{}) orelse return error.Other;
    idx1 += 1;
    const idx2 = filename.findAscii(".", .{}) orelse return error.Other;
    const session_num = filename.view(idx1, idx2);
    try html.addUtf8("\t<title>Сеанс ");
    try html.addView(session_num);
    try html.addUtf8(" - Закон Одного</title>\n</head>\n<body><div class=session>Сеанс ");
    try html.addView(session_num);
    try html.addAscii("</div>\n<div class=session_date>");
    const date = lines.orderedRemove(0);
    try html.addView(date);
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

        if (line.startsWithAscii(new_question_prefix)) {
            who_speaks = null;
            if (last_was != null) {
                try html.addAscii("</td>\n\t</tr>\n</table>");
            }
            last_was = .anchor;
            try html.addAscii("\n<table>\n\t<tr>\n\t\t<td>");
            // mtl.debug(@src(), "{f}, {f}", .{line._(2), session_num._(2)});
            var bh = try buildAHref(alloc, line, try session_num.toString());
            defer bh.deinit();
            try html.add(bh);
            try html.addAscii("</td>");
        } else if (line.startsWithAscii(en_prefix)) {
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

            const from: usize = line.start + en_prefix.len;
            var en = line.mid(from);
            who_speaks = try addEng(&html, &en, who_speaks);
        } else if (line.startsWithAscii(ru_prefix)) {
            last_was = .ru;
            try html.addAscii("</td>\n\t</tr>\n\t<tr>\n\t\t<td></td>\n\t\t<td class=\"rus\">");
            const from: usize = line.start + ru_prefix.len;
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

    var html_filename = try filename.clone(.{});
    defer html_filename.deinit();
    try html_filename.changeToAsciiExtension(".html");
    var relative_path = try Ctring.New(tloo_path);
    defer relative_path.deinit();
    try relative_path.add(html_filename);

    var save_to_path = try io.getHome2(alloc, relative_path);
    defer save_to_path.deinit();

    var utf8 = try save_to_path.toBytes(alloc, .{});
    defer utf8.deinit(alloc);

    const out_file = try std.fs.createFileAbsolute(utf8.items, .{});
    defer out_file.close();

    var byte_buf = try html.toBytes(alloc, .{});
    defer byte_buf.deinit(alloc);

    try out_file.writeAll(byte_buf.items);
}
