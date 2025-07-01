const std = @import("std");
const Str = @import("String.zig");
const mtl = @import("mtl.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{NotFound};

pub const Folder = enum(u8) {
    Home,
    Config,
};

pub fn getEnv(a: Allocator, folder: Folder) ![]const u8 {
    const var_name = switch (folder) {
        Folder.Home => "HOME",
        else => return Error.NotFound,
    };

    return std.process.getEnvVarOwned(a, var_name) catch return Error.NotFound;
}

pub fn getHome(alloc: Allocator, subpath: ?Str) !Str {
    const home = try getEnv(alloc, Folder.Home);
    defer alloc.free(home);
    if (subpath) |s| {
        var ret = Str.New();
        try ret.addAsciiSlice(home);
        try ret.add(s);
        return ret;
    } else {
        return Str.From(home);
    }
}

pub fn getHomeSlice(alloc: Allocator, subpath: ?[]const u8) !Str {
    if (subpath) |utf8| {
        const s = try Str.From(utf8);
        defer s.deinit();
        return try getHome(alloc, s);
    }
    return try getHome(alloc, null);
}

pub fn listFiles(alloc: Allocator, fullpath: Str) !std.ArrayList(std.fs.Dir.Entry) {
    const bytes = try fullpath.toUtf8();
    defer bytes.deinit();
    var dir = try openDirUtf8(bytes.items);
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
    const bytes = try fullpath.toUtf8();
    defer bytes.deinit();
    return openDirUtf8(bytes.items);
}

pub fn openDirUtf8(fullpath: []const u8) !std.fs.Dir {
    const dir = try std.fs.openDirAbsolute(fullpath, .{.iterate=true, .no_follow = true});
    return dir;
}

pub fn readFile(alloc: Allocator, full_path: Str) ![]u8 {
    const bytes = try full_path.toUtf8();
    defer bytes.deinit();
    return readFileUtf8(alloc, bytes.items);
}

pub fn readFileUtf8(alloc: Allocator, full_path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();
    return file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
}

