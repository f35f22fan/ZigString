pub const DesktopFile = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const KVHash = std.StringHashMap(Ctring);
const GroupHash = std.StringHashMap(KVHash);

const io = @import("io.zig");

const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");
const ScriptsData = @import("ScriptsData");

const Ctring = @import("Ctring.zig").Ctring;
const mtl = Ctring.mtl;
const CaseSensitive = Ctring.CaseSensitive;
const Codepoint = Ctring.Codepoint;
const CodepointSlice = Ctring.CpSlice;
const Context = Ctring.Context;
const CpSlice = Ctring.CpSlice;
const Error = Ctring.Error;
const Index = Ctring.Index;
const KeepEmptyParts = Ctring.KeepEmptyParts;

groups: GroupHash = undefined,
comment: ?Ctring = null,
fullpath: ?Ctring = null,
name: ?Ctring = null,
exec: ?Ctring = null,
icon: ?Ctring = null,
alloc: Allocator = undefined,

const CstrMainGroup = "Desktop Entry";
const CstrName = "Name";
const CstrComment = "Comment";
const CstrExec = "Exec";
const CstrIcon = "Icon";
const CstrGenericName = "GenericName";
const CstrMimeType = "MimeType";
const CstrCategories = "Categories";
const CstrActions = "Actions";

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

pub fn NewCstr(a: Allocator, fullpath: []const u8) !DesktopFile {
    return New(a, try Ctring.New(fullpath));
}

pub fn New(a: Allocator, fullpath: Ctring) !DesktopFile {
    var desktop_file = DesktopFile{
        .alloc = a,
        .groups = GroupHash.init(a),
    };
    desktop_file.fullpath = fullpath;
    try desktop_file.init();

    return desktop_file;
}

pub fn deinit(self: *DesktopFile) void {

    var groups_iter = self.groups.iterator();
    while (groups_iter.next()) |group_kv|
    {
        self.alloc.free(group_kv.key_ptr.*);
        var value_hash = group_kv.value_ptr;
        var iter = value_hash.iterator();
        while (iter.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
        }
        value_hash.deinit();
    }

    self.groups.deinit();
    
    if (self.fullpath) |*k| {
        k.deinit();
    }
}

fn buildKeyname(a: Allocator, name: []const u8, lang: []const u8) !ArrayList(u8) {
    var key = try Ctring.New(name);
    defer key.deinit();
    try key.addAscii("[");
    try key.addAscii(lang);
    try key.addAscii("]");
    return key.toBytes(a, .{});
}

pub fn getActions(self: DesktopFile) ?*const Ctring {
    return self.getField(CstrActions, null, null);
}

pub fn getCategories(self: DesktopFile) ?*const Ctring {
    return self.getField(CstrCategories, null, null);
}

pub fn getComment(self: DesktopFile, lang: ?[]const u8) ?*const Ctring {
    return self.getField(CstrComment, lang, null);
}

pub fn getExec(self: DesktopFile) ?*const Ctring {
    return self.getField(CstrExec, null, null);
}

pub fn getField(self: DesktopFile, name: []const u8, lang: ?[]const u8,
group_name: ?[]const u8) ?*const Ctring {
    const gn = if (group_name) |cstr| cstr else CstrMainGroup;
    const group = self.groups.getPtr(gn) orelse return null;
    if (lang) |lang_cstr| {
        var key_name = buildKeyname(self.alloc, name, lang_cstr) catch return null;
        defer key_name.deinit(self.alloc);
        return group.getPtr(key_name.items);
    }
    
    return group.getPtr(name);
}

pub fn getGenericName(self: DesktopFile, lang: ?[]const u8) ?*const Ctring {
    return self.getField(CstrGenericName, lang, null);
}

pub fn getIcon(self: DesktopFile) ?*const Ctring {
    return self.getField(CstrIcon, null, null);
}

pub fn getMimeTypes(self: DesktopFile) ?*const Ctring {
    return self.getField(CstrMimeType, null, null);
}

pub fn getName(self: DesktopFile, lang: ?[]const u8) ?*const Ctring {
    return self.getField(CstrName, lang, null);
}

pub fn init(self: *DesktopFile) !void {
    const fp = self.fullpath orelse return error.NotFound;
    var fp_buf = try fp.toBytes(self.alloc, .{});
    defer fp_buf.deinit(self.alloc);
    var file_contents = try io.readFileUtf8(self.alloc, fp_buf.items);
    defer file_contents.deinit(self.alloc);

    var data_str = try Ctring.New(file_contents.items);
    defer data_str.deinit();
    // data_str.printStats(@src());
    const view = data_str.view(0, data_str.afterLast());
    var lines = try view.splitAscii("\n", false);
    defer lines.deinit(self.alloc);

    var current_hash: ?*KVHash = null;
// mtl.debug(@src(), "lines.count={}", .{lines.items.len});
    for (lines.items) |line| {
        if (line.startsWithAscii("#")) {
            continue;
        }
        if (line.isBetween("[", "]")) |group_name| {
            const name_cstr = try group_name.toOwnedSlice(self.alloc);
            const h = KVHash.init(self.alloc);
            try self.groups.put(name_cstr, h);
            current_hash = self.groups.getPtr(name_cstr) orelse break;
            continue;
        }
        
        if (line.findAscii("=", null) == null) {
            continue;
        }
            
        var kv_hash: *KVHash = current_hash orelse {
            mtl.trace(@src());
            break;
        };
        var arr = try line.splitAscii("=", false);
        defer arr.deinit(self.alloc);
        if (arr.items.len == 2) {
            const value_view = arr.items[1];
            const key = try arr.items[0].toOwnedSlice(self.alloc);
            try kv_hash.put(key, try value_view.toString());
        }
    }
}
