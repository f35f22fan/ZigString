const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

const mio = @import("io.zig");
const BitData = @import("bit_data.zig").BitData;
const mtl = @import("mtl.zig");
const Num = @import("Num.zig");

const Ctring = @import("Ctring.zig").Ctring;
const View = Ctring.View;

const Error = error {NotLocalFileHeader};
const Compression = enum(u16) {
    None = 0,
    Shrunk = 1,
    Reduced1 = 2,
    Reduced2 = 3,
    Reduced3 = 4,
    Reduced4 = 5,
    Imploded = 6,
    Deflated = 8,
    EnhancedDeflated = 9,
    PkwareDCLImploded = 10,
    BZIP2 = 12,
    LZMA = 14,
    IBM_TERSE = 18,
    IBM_L7ZZ = 19,
    PPMd_1_1 = 98,

    fn fromU16(cmpr: u16) Compression {
        return switch (cmpr)  {
            @intFromEnum(Compression.None) => .None,
            @intFromEnum(Compression.Shrunk) => .Shrunk,
            @intFromEnum(Compression.Reduced1) => .Reduced1,
            @intFromEnum(Compression.Reduced2) => .Reduced2,
            @intFromEnum(Compression.Reduced3) => .Reduced3,
            @intFromEnum(Compression.Reduced4) => .Reduced4,
            @intFromEnum(Compression.Imploded) => .Imploded,
            @intFromEnum(Compression.Deflated) => .Deflated,
            @intFromEnum(Compression.EnhancedDeflated) => .EnhancedDeflated,
            @intFromEnum(Compression.PkwareDCLImploded) => .PkwareDCLImploded,
            @intFromEnum(Compression.BZIP2) => .BZIP2,
            @intFromEnum(Compression.LZMA) => .LZMA,
            @intFromEnum(Compression.IBM_TERSE) => .IBM_TERSE,
            @intFromEnum(Compression.IBM_L7ZZ) => .IBM_L7ZZ,
            @intFromEnum(Compression.PPMd_1_1) => .PPMd_1_1,
            else => .None,
        };
    }
};

const DateTime = struct {
    year: u16 = 0,
    month: u8 = 0,
    day_of_month: u8 = 0,
    hours: u8 = 0,
    minutes: u8 = 0,
    seconds: u8 = 0,

    fn fromMsDos(mod_date: u16, mod_time: u16) ?DateTime {
        // 2025.02.18 8:27
        mtl.debug(@src(), "mod_date:{}, mod_time:{}", .{mod_date, mod_time});
        var dt: DateTime = .{};
        dt.day_of_month = @truncate(mod_date & 0x1F); // bits 0-4
        dt.month = @truncate((mod_date & 0x1E0) >> 5); // bits 5-8
        dt.year = 1980 + ((mod_date & 0xFE00) >> 9); // bits 9-15
        mtl.debug(@src(), "year:{}, month:{}, day:{}", .{dt.year, dt.month, dt.day_of_month});

        dt.seconds = @truncate((mod_time & 0x1F) * 2); // bits 0-4
        dt.minutes = @truncate((mod_time & 0x7E0) >> 5); // bits 5-10
        dt.hours = @truncate((mod_time & 0xF800) >> 11);
        mtl.debug(@src(), "h:{}, m:{}, s:{}", .{dt.hours, dt.minutes, dt.seconds});

        // var ts: std.Io.Timestamp = .zero;
        // var d: std.Io.Duration = .{};

        // ts.addDuration(d);

        _ = dt.toMsDos();
        return dt;
    }

    fn toMsDos(self: DateTime) [2]u16 {
        var mod_date: u16 = (self.year - 1980) << 9;
        mod_date |= @as(u16, self.month) << 5;
        mod_date |= @as(u16, self.day_of_month);

        var mod_time: u16 = @as(u16, self.hours) << 11;
        mod_time |= @as(u16, self.minutes) << 5;
        mod_time |= @as(u16, self.seconds) / 2;

        mtl.debug(@src(), "mod_date:{}, mod_time:{}", .{mod_date, mod_time});
        return .{mod_date, mod_time};
    }
};

const Descriptor = struct {
    crc_32: u32 = 0,
    compressed_size: u32 = 0,
    uncompressed_size: u32 = 0,

    fn read(self: *Descriptor, buf: []const u8, idx: *usize) !void {
        self.crc_32 = try toU32(buf[idx.*..]);
        // mtl.debug(@src(), "crc_32: 0x{X}", .{lfh.descriptor.crc_32});
        idx.* += 4;
        self.compressed_size = try toU32(buf[idx.*..]);
        idx.* += 4;
        self.uncompressed_size = try toU32(buf[idx.*..]);
        idx.* += 4;
    }
};

pub const EndRecord = struct {
    disk_number: u16 = 0,
    disk_where_starts: u16 = 0,
    disk_entries: u16 = 0,
    total_entries: u16 = 0,
    cd_size: u32 = 0,
    offset: u32 = 0,
    comment_len: u16 = 0,
    comment: ?[]const u8 = null,

    pub fn deinit(self: EndRecord, a: Allocator) void {
        if (self.comment) |c| {
            a.free(c);
        }
    }

    fn read(alloc: Allocator, buf: []const u8, from: *usize) !EndRecord {
        _ = &alloc;
        const signature = "\x50\x4b\x05\x06";
        var idx = from.*;

        if (!std.mem.startsWith(u8, buf[idx..], signature)) {
            return error.NotLocalFileHeader;
        }

        idx += signature.len;
        mtl.debug(@src(), "Found signature of End Record", .{});
        
        var h: EndRecord = .{};
        h.disk_number = try toU16(buf[idx..]);
        idx += 2;

        h.disk_where_starts = try toU16(buf[idx..]);
        idx += 2;

        h.disk_entries = try toU16(buf[idx..]);
        idx += 2;

        h.total_entries = try toU16(buf[idx..]);
        idx += 2;

        h.cd_size = try toU32(buf[idx..]);
        idx += 4;

        h.offset = try toU32(buf[idx..]);
        idx += 4;

        h.comment_len = try toU16(buf[idx..]);
        idx += 2;

        if (h.comment_len != 0) {
            const new_buf = try alloc.alloc(u8, h.comment_len + 1);
            @memcpy(new_buf[0..h.comment_len], buf[idx..idx + h.comment_len]);
            new_buf[h.comment_len] = 0;
            h.comment = new_buf;
            mtl.debug(@src(), "zip comment:\"{s}\"", .{new_buf});
            idx += h.comment_len;
        }

        from.* = idx;

        return h;
    }
};

pub const CentralDirFileHeader = struct {
    version: u16 = 0,
    version_needed: u16 = 0,
    flags: u16 = 0,
    compression: u16 = 0,
    mod_time: u16 = 0,
    mod_date: u16 = 0,
    crc_32: u32 = 0,
    descriptor: Descriptor = .{},
    filename_len: u16 = 0,
    extra_field_len: u16 = 0,
    comment_len: u16 = 0,
    disk_number: u16 = 0,
    internal_attr: u16 = 0,
    external_attr: u32 = 0,
    local_header_offset: u32 = 0,
    filename: ?[]const u8 = null,
    extra_field: ?[]const u8 = null,
    comment: ?[]const u8 = null,

    pub fn deinit(self: CentralDirFileHeader, a: Allocator) void {
        if (self.filename) |s| {
            a.free(s);
        }

        if (self.extra_field) |s| {
            a.free(s);
        }

        if (self.comment) |s| {
            a.free(s);
        }
    }

    pub fn read(alloc: Allocator, buf: []const u8, from: *usize) !CentralDirFileHeader {
        _ = &alloc;
        const signature = "\x50\x4b\x01\x02";
        var idx = from.*;

        if (!std.mem.startsWith(u8, buf[idx..], signature)) {
            mtl.debug(@src(), "IDX: {}", .{idx});
            return error.NotLocalFileHeader;
        }

        idx += signature.len;

        var h: CentralDirFileHeader = .{};
        h.version = try toU16(buf[idx..]);
        mtl.debug(@src(), "version=0x{X}, upper={}, lower:{}",
            .{h.version, (h.version & 0xFF00) >> 8, h.version & 0x00FF});
        idx += 2;

        h.version_needed = try toU16(buf[idx..]);
        idx += 2;

        h.flags = try toU16(buf[idx..]);
        idx += 2;

        h.compression = try toU16(buf[idx..]);
        idx += 2;
        mtl.debug(@src(), "compression:{}", .{h.compression});

        h.mod_time = try toU16(buf[idx..]);
        idx += 2;
        h.mod_date = try toU16(buf[idx..]);
        idx += 2;

        try h.descriptor.read(buf, &idx);

        h.filename_len = try toU16(buf[idx..]);
        idx += 2;

        h.extra_field_len = try toU16(buf[idx..]);
        idx += 2;

        h.comment_len = try toU16(buf[idx..]);
        idx += 2;

        h.disk_number = try toU16(buf[idx..]);
        idx += 2;

        h.internal_attr = try toU16(buf[idx..]);
        idx += 2;

        h.external_attr = try toU32(buf[idx..]);
        idx += 4;

        h.local_header_offset = try toU32(buf[idx..]);
        idx += 4;

        if (h.filename_len != 0) {
            const new_buf = try alloc.alloc(u8, h.filename_len + 1);
            @memcpy(new_buf[0..h.filename_len], buf[idx..idx + h.filename_len]);
            new_buf[h.filename_len] = 0;
            h.filename = new_buf;
            mtl.debug(@src(), "filename:\"{s}\"", .{new_buf});
            idx += h.filename_len;
        }

        if (h.extra_field_len != 0) {
            if (true) {
                const new_buf = try alloc.alloc(u8, h.extra_field_len);
                @memcpy(new_buf[0..], buf[idx..idx + h.extra_field_len]);
                h.extra_field = new_buf;
            }
            idx += h.extra_field_len;
        }

        if (h.comment_len != 0) {
            if (true) {
                const new_buf = try alloc.alloc(u8, h.comment_len + 1);
                @memcpy(new_buf[0..h.comment_len], buf[idx..idx + h.comment_len]);
                new_buf[h.comment_len] = 0;
                h.comment = new_buf;
                mtl.debug(@src(), "comment:\"{s}\"", .{new_buf});
            }
            idx += h.comment_len;
        }

        from.* = idx;

        return h;
    }
};

pub const LocalFileHeader = struct {
    version: u16 = 0,
    flags: u16 = 0,
    compression: Compression = .None,
    last_modified: ?DateTime = null,
    mod_time: u16 = 0,
    mod_date: u16 = 0,
    descriptor: Descriptor = .{},
    filename_len: u16 = 0,
    extra_field_len: u16 = 0,
    filename: ?[]const u8 = null,
    extra_field: ?[]const u8 = null,
    data: ?[]const u8 = null,
    data_descriptor: ?Descriptor = null,

    pub fn deinit(self: LocalFileHeader, a: Allocator) void {
        if (self.filename) |name| {
            a.free(name);
        }
    }

    fn printFlags(self: LocalFileHeader) void {
        for (0..15) |i| {
            const y = @shlExact(@as(u16, 1), @as(u4, @truncate(i)));
            const val: u16 = if (self.flags & y == 0) 0 else 1;
            mtl.debug(@src(), "bit:{} = {}", .{i, val});
        }
    }

    pub fn read(alloc: Allocator, buf: []const u8, from: *usize) !LocalFileHeader {
        const signature = "\x50\x4b\x03\x04";
        var idx = from.*;

        if (!std.mem.startsWith(u8, buf[idx..], signature)) {
            return error.NotLocalFileHeader;
        }

        idx += signature.len;
        
        var h: LocalFileHeader = .{};
        h.version = try toU16(buf[idx..]);
        mtl.debug(@src(), "version={}", .{h.version});
        idx += 2;

        h.flags = try toU16(buf[idx..]);
        idx += 2;

        const cmpr = try toU16(buf[idx..]);
        h.compression = Compression.fromU16(cmpr);
        mtl.debug(@src(), "Compression: {any}", .{h.compression});

        idx += 2;
        const mod_time: u16 = try toU16(buf[idx..]);
        idx += 2;
        const mod_date: u16 = try toU16(buf[idx..]);
        h.last_modified = DateTime.fromMsDos(mod_date, mod_time);
        idx += 2;

        try h.descriptor.read(buf, &idx);

        h.filename_len = try toU16(buf[idx..]);
        idx += 2;
        h.extra_field_len = try toU16(buf[idx..]);
        idx += 2;

        mtl.debug(@src(), "Compressed size: {}, uncompressed:{} fn_len:{}, ef_len:{}",
        .{h.descriptor.compressed_size, h.descriptor.uncompressed_size, h.filename_len, h.extra_field_len});

        if (h.filename_len != 0) {
            const new_buf = try alloc.alloc(u8, h.filename_len + 1);
            @memcpy(new_buf[0..h.filename_len], buf[idx..idx + h.filename_len]);
            new_buf[h.filename_len] = 0;
            // const s = try alloc.dupeSentinel(u8, buf[idx..idx + lfh.filename_len], 0);
            h.filename = new_buf;
            mtl.debug(@src(), "filename:\"{s}\"", .{new_buf});
            idx += h.filename_len;
        }

        if (h.extra_field_len != 0) {
            const new_buf = try alloc.alloc(u8, h.filename_len);
            @memcpy(new_buf[0..h.filename_len], buf[idx..idx + h.filename_len]);
            h.extra_field = new_buf;
            idx += h.extra_field_len;
        }

        if (h.descriptor.compressed_size != 0) {
            h.data = buf[idx..idx + h.descriptor.compressed_size];
            idx += h.descriptor.compressed_size;
        }

        if (h.flags & 4 != 0) { // bit 3
            var descr: Descriptor = .{};
            try descr.read(buf, &idx);
            h.data_descriptor = descr;
        }

        from.* = idx;

        return h;
    }
};



test "Read Zip" {
    if (false)
        return error.SkipZigTest;
    
    const io = std.testing.io;
    const alloc = std.testing.allocator;

    if (false) {
        return;
    }

    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    const fullpath = "/home/fox/Downloads/CreateFormulaFunctions.ods";
    var arr = try mio.readFileUtf8(alloc, io, fullpath);
    defer arr.deinit(alloc);

    var many: std.ArrayList(LocalFileHeader) = .empty;
    defer {
        for (many.items) |item| {
            item.deinit(alloc);
        }
        many.deinit(alloc);
    }

    var idx: usize = 0;
    while (true) {
        const local_file = LocalFileHeader.read(alloc, arr.items[0..], &idx) catch break;
        try many.append(alloc, local_file);
        // mtl.debug(@src(), "Ended at: {}\n==================\n\n", .{idx});
        if (local_file.data) |data| {
            if (local_file.filename) |name| {
                try mio.toNewFile(io, "/home/fox/Documents/ZigOut.txt", name, .No);
                try mio.toNewFile(io, "/home/fox/Documents/ZigOut.txt", ":\n\n", .No);
            }
            try mio.toNewFile(io, "/home/fox/Documents/ZigOut.txt", data, .No);
        }
    }

    var central_headers: std.ArrayList(CentralDirFileHeader) = .empty;
    defer {
        for (central_headers.items) |item| {
            item.deinit(alloc);
        }

        central_headers.deinit(alloc);
    }

    while (true) {
        const h = CentralDirFileHeader.read(alloc, arr.items[0..], &idx) catch break;
        try central_headers.append(alloc, h);
        mtl.debug(@src(), "Ended at: {}\n==================\n\n", .{idx});
    }

    const end_record = try EndRecord.read(alloc, arr.items[0..], &idx);
    defer end_record.deinit(alloc);
    mtl.debug(@src(), "REACHED THE END!!!", .{});

    
}


inline fn toU32(arr: []const u8) !u32 {
    // var ret: u32 = @as(u32, d) << 24;
    // ret |= @as(u32, c) << 16;
    // ret |= @as(u32, b) << 8;
    // ret |= a;
    
    //return ret;
    var reader: std.Io.Reader = .fixed(arr);
    const ret: u32 = @bitCast(try reader.takeInt(u32, .little));

    return ret;
}

inline fn toU16(arr: []const u8) !u16 {
    // var flags: u16 = @as(u16, a);
    // flags |= @as(u16, b) << 8;
    
    // return flags;
    var reader: std.Io.Reader = .fixed(arr);
    const ret: u16 = @bitCast(try reader.takeInt(u16, .little));

    return ret;
}
