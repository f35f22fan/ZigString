const std = @import("std");
const Str = @import("String.zig");
const mtl = @import("mtl.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{NotFound};

pub const Folder = enum(u8) {
    Home,
    Config,
};

pub fn changeExtension(filename: Str, ext: []const u8) !Str {
    const pt_idx = filename.lastIndexOfBytes(".") orelse return Str.Error.Other;
    var out_name = try filename.betweenIndices(.{}, pt_idx);
    try out_name.addBytes(ext);

    return out_name;
}

pub fn getEnv(a: Allocator, folder: Folder) ![]const u8 {
    const var_name = switch (folder) {
        Folder.Home => "HOME",
        else => return Error.NotFound,
    };

    return std.process.getEnvVarOwned(a, var_name) catch return Error.NotFound;
}

pub fn getHome(alloc: Allocator, subpath: ?[] const u8) ![]const u8 {
    const home = try getEnv(alloc, Folder.Home);
    if (subpath) |s| {
        defer alloc.free(home);
        var list = std.ArrayList(u8).init(alloc);
        defer list.deinit();
        try list.appendSlice(home);
        try list.appendSlice(s);
        return list.toOwnedSlice();
    } else {
        return home;
    }
}

pub fn listFiles(alloc: Allocator, fullpath: Str) !std.ArrayList(std.fs.Dir.Entry) {
    const bytes = try fullpath.toBytes();
    defer bytes.deinit();
    var dir = try std.fs.openDirAbsolute(bytes.items, .{.iterate=true, .no_follow = true});
    defer dir.close();
    var iter = dir.iterate();

    var list = std.ArrayList(std.fs.Dir.Entry).init(alloc);

    while (try iter.next()) |entry| {
        try list.append(.{.kind = entry.kind, .name = try alloc.dupe(u8, entry.name)});
        // mtl.debug(@src(), "\"{s}\", kind={}", .{entry.name, entry.kind});
    }

    return list;
}

pub fn openDir(fullpath: Str) !std.fs.Dir {
    const bytes = try fullpath.toBytes();
    defer bytes.deinit();
    return openDirBytes(bytes.items);
}

pub fn openDirBytes(fullpath: []const u8) !std.fs.Dir {
    const dir = try std.fs.openDirAbsolute(fullpath, .{.iterate=true, .no_follow = true});
    return dir;
}

pub fn readFile(alloc: Allocator, full_path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();
    return file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
}

