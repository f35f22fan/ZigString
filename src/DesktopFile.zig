pub const DesktopFile = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const KVHash = std.StringHashMap(String);
const GroupHash = std.StringHashMap(KVHash);

const zigstr = @import("zigstr");
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

groups: GroupHash = undefined,
comment: ?String = null,
fullpath: ?String = null,
name: ?String = null,
exec: ?String = null,
icon: ?String = null,
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

pub fn NewCstr(a: Allocator, fullpath: []const u8) !DesktopFile {
    return New(a, try String.From(fullpath));
}

pub fn New(a: Allocator, fullpath: String) !DesktopFile {
    var df = DesktopFile{
        .alloc = a,
        .groups = GroupHash.init(a),
    };
    df.fullpath = fullpath;
    try df.init();

    return df;
}

pub fn deinit(self: *DesktopFile) void {

    var groups_iter = self.groups.iterator();
    while (groups_iter.next()) |group_kv|
    {
        const name = group_kv.key_ptr;
        self.alloc.free(name.*);
        var value = group_kv.value_ptr;
        var iter = value.iterator();
        while (iter.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
        }
        value.deinit();
    }

    self.groups.deinit();
    
    if (self.fullpath) |k| {
        k.deinit();
    }
}

fn buildKeyname(name: []const u8, lang: []const u8) !ArrayList(u8) {
    var key = try String.From(name);
    defer key.deinit();
    try key.addChar('[');
    try key.addUtf8(lang);
    try key.addChar(']');
    return key.toBytes();
}

pub fn getActions(self: DesktopFile) ?*const String {
    return self.getField(CstrActions, null, null);
}

pub fn getCategories(self: DesktopFile) ?*const String {
    return self.getField(CstrCategories, null, null);
}

pub fn getComment(self: DesktopFile, lang: ?[]const u8) ?*const String {
    return self.getField(CstrComment, lang, null);
}

pub fn getExec(self: DesktopFile) ?*const String {
    return self.getField(CstrExec, null, null);
}

pub fn getField(self: DesktopFile, name: []const u8, lang: ?[]const u8,
group_name: ?[]const u8) ?*const String {
    const gn = if (group_name) |cstr| cstr else CstrMainGroup;
    const group = self.groups.getPtr(gn) orelse return null;
    if (lang) |lang_cstr| {
        const key_name = buildKeyname(name, lang_cstr) catch return null;
        defer key_name.deinit();
        return group.getPtr(key_name.items);
    }
    
    return group.getPtr(name);
}

pub fn getGenericName(self: DesktopFile, lang: ?[]const u8) ?*const String {
    return self.getField(CstrGenericName, lang, null);
}

pub fn getIcon(self: DesktopFile) ?*const String {
    return self.getField(CstrIcon, null, null);
}

pub fn getMimeTypes(self: DesktopFile) ?*const String {
    return self.getField(CstrMimeType, null, null);
}

pub fn getName(self: DesktopFile, lang: ?[]const u8) ?*const String {
    return self.getField(CstrName, lang, null);
}

pub fn init(self: *DesktopFile) !void {
    const fp = self.fullpath orelse return String.Error.NotFound;
    const path_buf = try fp.toBytes();
    defer path_buf.deinit();
    const data_cstr = try io.readFile(self.alloc, path_buf.items);

    const data_str = try String.From(data_cstr);
    self.alloc.free(data_cstr);
    defer data_str.deinit();
    var lines = try data_str.split("\n", .{.keep = .No});
    defer {
        for (lines.items) |line| {
            line.deinit();
        }
        lines.deinit();
    }

    var current_hash_opt: ?*KVHash = null;

    for (lines.items) |line| {
        if (line.startsWithBytes("#", .{})) {
            line.print(@src(), "Comment: ");
            continue;
        }
        if (line.isBetween("[", "]")) |group_name| {
            defer group_name.deinit();
            const name_cstr = try group_name.dupAsCstr();
            const h = KVHash.init(self.alloc);
            try self.groups.put(name_cstr, h);
            current_hash_opt = self.groups.getPtr(name_cstr) orelse break;
            continue;
        }
        //try line.print(std.debug, "Line: ");
        var current_hash: *KVHash = current_hash_opt orelse break;
        var kv = try line.split("=", .{});
        defer {
            for (kv.items) |s| {
                s.deinit();
            }
            kv.deinit();
        }

        const key = try kv.items[0].Clone();
        defer key.deinit();
        const value = if (kv.items.len == 2) try kv.items[1].Clone() else String.New();
        const final_key = try key.dupAsCstrAlloc(self.alloc);
        // std.debug.print("\"{s}\"=>\"{s}{}{s}\"\n",
        // .{final_key, String.COLOR_BLUE, value, String.COLOR_DEFAULT});
        try current_hash.put(final_key, value);
    }
}

fn put(a: Allocator, key: String, value: String, dest: *KVHash) !void {
    std.debug.print("{s}(): key=\"{s}\", value=\"{}\"\n", .{ @src().fn_name, key, value });
    if (key.isEmpty()) {
        const cstr_key = try a.dupe(u8, "");
        
        try dest.put(cstr_key, value);
    } else {
        const cstr_key = try key.dup_as_cstr_alloc(a);
        try dest.put(cstr_key, value);
    }
}


