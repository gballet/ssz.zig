const std = @import("std");
const lib = @import("./lib.zig");
const serialize = lib.serialize;
const deserialize = lib.deserialize;
const isFixedSizeObject = lib.isFixedSizeObject;
const ArrayList = std.ArrayList;

pub fn List(comptime T: type, comptime max_size: usize) type {
    return struct {
        const Self = @This();
        const Len = std.math.IntFittingRange(0, max_size);
        const Item = T;

        len: Len,
        buffer: [max_size]T = undefined,

        pub fn sszEncode(self: *const Self, l: *ArrayList(u8)) !void {
            // BitList[N]
            if (Self.Item == bool) {
                var byte: u8 = 0;
                for (self.buffer, 0..) |bit, index| {
                    if (bit) {
                        byte |= @as(u8, 1) << @as(u3, @truncate(index));
                    }

                    if (index % 8 == 7) {
                        try l.append(byte);
                        byte = 0;
                    }
                }

                // Write the last byte if the length
                // is not byte-aligned
                if (self.len % 8 != 0) {
                    try l.append(byte);
                }
            } else // List[N]
            if (try isFixedSizeObject(Self.Item)) {
                var i: usize = 0;
                while (i < self.len) : (i += 1) {
                    try serialize(Self.Item, self.buffer[i], l);
                }
            } else {
                var start = l.items.len;

                // Reserve the space for the offset
                const offset = [_]u8{ 0, 0, 0, 0 };
                for (self.buffer) |_| {
                    _ = try l.writer().write(offset[0..4]);
                }

                // Now serialize one item after the other
                // and update the offset list with its location.
                for (self.buffer) |item| {
                    std.mem.writeInt(u32, l.items[start .. start + 4][0..4], @as(u32, @truncate(l.items.len)), std.builtin.Endian.little);
                    _ = try serialize(Self.Item, item, l);
                    start += 4;
                }
            }
        }

        pub fn sszDecode(serialized: []const u8, out: *Self) !void {
            // BitList[N] or regular List[N]?
            if (Self.Item == bool) {
                for (serialized, 0..) |byte, bindex| {
                    var i = @as(u8, 0);
                    var b = byte;
                    while (bindex * 8 + i < out.len and i < 8) : (i += 1) {
                        out[bindex * 8 + i] = b & 1 == 1;
                        b >>= 1;
                    }
                }
            } else if (try isFixedSizeObject(Self.Item)) {
                out.len = 0;
                var i: usize = 0;
                const pitch = @sizeOf(Self.Item);
                while (i < serialized.len) : (i += pitch) {
                    try deserialize(Self.Item, serialized[i .. i + pitch], &out.buffer[out.len]);
                    out.len += 1;
                }
            } else {
                // first variable index is also the size of the list
                // of indices. Recast that list as a []const u32.
                const size = std.mem.readInt(u32, serialized[0..4], std.builtin.Endian.little) / @sizeOf(u32);
                const indices = std.mem.bytesAsSlice(u32, serialized[0 .. size * 4]);
                var i = @as(usize, 0);
                while (i < size) : (i += 1) {
                    const end = if (i < size - 1) indices[i + 1] else serialized.len;
                    const start = indices[i];
                    if (start >= serialized.len or end > serialized.len) {
                        return error.IndexOutOfBounds;
                    }
                    try deserialize(Self.Item, serialized[start..end], &out.buffer[i]);
                }
            }
        }

        pub fn init(len: usize) error{Overflow}!Self {
            if (len > max_size) return error.Overflow;
            return Self{ .len = @intCast(len) };
        }

        pub fn eql(self: *const Self, other: *Self) bool {
            return (self.len == other.len) and std.mem.eql(Self.Item, self.buffer[0..self.len], other.buffer[0..self.len]);
        }

        pub fn append(self: *Self, item: Self.Item) error{Overflow}!void {
            if (self.len == max_size) {
                return error.Overflow;
            }

            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn slice(self: *Self) []T {
            return self.buffer[0..self.len];
        }

        pub fn fromSlice(m: []const T) error{Overflow}!Self {
            var list = try init(m.len);
            @memcpy(list.slice(), m);
            return list;
        }

        pub fn get(self: Self, i: usize) T {
            return self.slice()[i];
        }

        pub fn set(self: *Self, i: usize, item: T) void {
            self.slice()[i] = item;
        }

        pub fn fromBoundedArrayAligned(baa: anytype) error{Overflow}!Self {
            return fromSlice(baa.slice());
        }
    };
}
