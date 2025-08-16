const std = @import("std");
const Str = @import("String.zig");
const mtl = @import("mtl.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{NotFound};

pub const Folder = enum(u8) {
    Home,
    Config,
};

const FileEntry = struct {
    kind: std.fs.File.Kind,
    name: []const u8,

    pub fn From(alloc: Allocator, entry: std.fs.Dir.Entry) !FileEntry {
        return .{.kind = entry.kind, .name = try alloc.dupe(u8, entry.name)};
    }

    pub fn deinit(self: FileEntry, alloc: Allocator) void {
        alloc.free(self.name);
    }
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

pub fn listFiles(alloc: Allocator, folder: ?Folder, subdir: ?Str) !std.ArrayList(FileEntry) {
    var dir : std.fs.Dir = undefined;

    var fullpath: Str = Str.New();
    defer fullpath.deinit();

    if (folder) |f| {
        fullpath = switch (f) {
            .Home => try getHome(alloc, null),
            .Config => return error.BadArg, // to be implemented!
        };

        if (subdir) |subpath| {
            if (!subpath.startsWithCp('/')
                and !fullpath.endsWithCp('/')) {
                try fullpath.addAscii("/");
            }
            
            try fullpath.add(subpath);
        }
    } else {
        const utf8 = subdir orelse return error.BadArg;
        fullpath = try utf8.Clone();
    }
    
    mtl.debug(@src(), "{dt}", .{fullpath});
    const bytes = try fullpath.toUtf8();
    defer bytes.deinit();
    dir = try openDirUtf8(bytes.items);
    defer dir.close();
    var iter = dir.iterate();
    var list = std.ArrayList(FileEntry).init(alloc);
    errdefer {
        for (list.items) |item| {
            item.deinit(alloc);
        }
        list.deinit();
    }

    while (try iter.next()) |entry| {
        try list.append(try FileEntry.From(alloc, entry));
        // mtl.debug(@src(), "\"{s}\", kind={}", .{entry.name, entry.kind});
    }

    return list;
}

pub fn listFilesUtf8(alloc: Allocator, folder: ?Folder, subdir: ?[]const u8) !std.ArrayList(FileEntry) {
    var subpath: ?Str = null;
    defer {
        if (subpath) |sp| {
            sp.deinit();
        }
    }
    if (subdir) |sd| {
        subpath = try Str.From(sd);
    }
    return listFiles(alloc, folder, subpath);
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

