//! This module provides functions for serializing and deserializing
//! data structures with the SSZ method.

const std = @import("std");
const ArrayList = std.ArrayList;
const builtin = std.builtin;
const sha256 = std.crypto.hash.sha2.Sha256;
const hashes_of_zero = @import("./zeros.zig").hashes_of_zero;
const Allocator = std.mem.Allocator;

/// Number of bytes per chunk.
const BYTES_PER_CHUNK = 32;

/// Number of bytes per serialized length offset.
const BYTES_PER_LENGTH_OFFSET = 4;

// Determine the serialized size of an object so that
// the code serializing of variable-size objects can
// determine the offset to the next object.
fn serializedSize(comptime T: type, data: T) !usize {
    const info = @typeInfo(T);
    return switch (info) {
        .Array => data.len,
        .Pointer => switch (info.Pointer.size) {
            .Slice => data.len,
            else => serializedSize(info.Pointer.child, data.*),
        },
        .Optional => if (data == null)
            @as(usize, 1)
        else
            1 + try serializedSize(info.Optional.child, data.?),
        .Null => @as(usize, 0),
        else => error.NoSerializedSizeAvailable,
    };
}

/// Returns true if an object is of fixed size
fn isFixedSizeObject(comptime T: type) !bool {
    const info = @typeInfo(T);
    switch (info) {
        .Bool, .Int, .Null => return true,
        .Array => return false,
        .Struct => inline for (info.Struct.fields) |field| {
            if (!try isFixedSizeObject(field.type)) {
                return false;
            }
        },
        .Pointer => switch (info.Pointer.size) {
            .Many, .Slice, .C => return false,
            .One => return isFixedSizeObject(info.Pointer.child),
        },
        else => return error.UnknownType,
    }
    return true;
}

fn is_stable_container(comptime struc: std.builtin.Type.Struct) bool {
    return std.meta.hasMethod(struc, "ssz_serialize") and std.meta.hasMethod(struc, "sc_max_size");
}

/// Provides the generic serialization of any `data` var to SSZ. The
/// serialization is written to the `ArrayList` `l`.
pub fn serialize(comptime T: type, data: T, l: *ArrayList(u8)) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Array => {
            // Bitvector[N] or vector?
            if (info.Array.child == bool) {
                var byte: u8 = 0;
                for (data, 0..) |bit, index| {
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
                if (data.len % 8 != 0) {
                    try l.append(byte);
                }
            } else {
                // If the item type is fixed-size, serialize inline,
                // otherwise, create an array of offsets and then
                // serialize each object afterwards.
                if (try isFixedSizeObject(info.Array.child)) {
                    for (data) |item| {
                        try serialize(info.Array.child, item, l);
                    }
                } else {
                    // Size of the buffer before anything is
                    // written to it.
                    var start = l.items.len;

                    // Reserve the space for the offset
                    for (data) |_| {
                        _ = try l.writer().writeInt(u32, 0, std.builtin.Endian.little);
                    }

                    // Now serialize one item after the other
                    // and update the offset list with its location.
                    for (data) |item| {
                        std.mem.writeInt(u32, l.items[start .. start + 4][0..4], @as(u32, @truncate(l.items.len)), std.builtin.Endian.little);
                        _ = try serialize(info.Array.child, item, l);
                        start += 4;
                    }
                }
            }
        },
        .Bool => {
            if (data) {
                try l.append(1);
            } else {
                try l.append(0);
            }
        },
        .Int => |int| {
            switch (int.bits) {
                8, 16, 32, 64, 128, 256 => {},
                else => return error.InvalidSerializedIntLengthType,
            }
            _ = try l.writer().writeInt(T, data, std.builtin.Endian.little);
        },
        .Pointer => {
            // Bitlist[N] or list?
            switch (info.Pointer.size) {
                .Slice, .One => {
                    if (@sizeOf(info.Pointer.child) == 1) {
                        _ = try l.writer().write(data);
                    } else {
                        for (data) |item| {
                            try serialize(@TypeOf(item), item, l);
                        }
                    }
                },
                else => return error.UnSupportedPointerType,
            }
        },
        .Struct => |struc| {
            // Check if this is a stable container: if all fields
            // are Optionals, and one constant is called `sc_max_fields`
            // then we consider it's a stable container.
            if (is_stable_container(struc)) {
                return data.ssz_serialize(data, l);
            }

            // First pass, accumulate the fixed sizes
            comptime var var_start = 0;
            inline for (info.Struct.fields) |field| {
                if (@typeInfo(field.type) == .Int or @typeInfo(field.type) == .Bool) {
                    var_start += @sizeOf(field.type);
                } else {
                    var_start += 4;
                }
            }

            // Second pass: intertwine fixed fields and variables offsets
            var var_acc = @as(usize, var_start); // variable part size accumulator
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Int, .Bool => {
                        try serialize(field.type, @field(data, field.name), l);
                    },
                    else => {
                        try serialize(u32, @as(u32, @truncate(var_acc)), l);
                        var_acc += try serializedSize(field.type, @field(data, field.name));
                    },
                }
            }

            // Third pass: add variable fields at the end
            if (var_acc > var_start) {
                inline for (info.Struct.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Int, .Bool => {
                            // skip fixed-size fields
                        },
                        else => {
                            try serialize(field.type, @field(data, field.name), l);
                        },
                    }
                }
            }
        },
        // Nothing to be added to the payload
        .Null => {},
        // Optionals are like unions, but their 0 value has to be 0.
        .Optional => {
            if (data != null) {
                _ = try l.writer().writeInt(u8, 1, std.builtin.Endian.little);
                try serialize(info.Optional.child, data.?, l);
            } else {
                _ = try l.writer().writeInt(u8, 0, std.builtin.Endian.little);
            }
        },
        .Union => {
            if (info.Union.tag_type == null) {
                return error.UnionIsNotTagged;
            }
            inline for (info.Union.fields, 0..) |f, index| {
                if (@intFromEnum(data) == index) {
                    _ = try l.writer().writeInt(u8, index, std.builtin.Endian.little);
                    try serialize(f.type, @field(data, f.name), l);
                    return;
                }
            }
        },
        else => {
            return error.UnknownType;
        },
    }
}

/// Takes a byte array containing the serialized payload of type `T` (with
/// possible trailing data) and deserializes it into the `T` object pointed
/// at by `out`.
pub fn deserialize(comptime T: type, serialized: []const u8, out: *T) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Array => {
            // Bitvector[N] or regular vector?
            if (info.Array.child == bool) {
                for (serialized, 0..) |byte, bindex| {
                    var i = @as(u8, 0);
                    var b = byte;
                    while (bindex * 8 + i < out.len and i < 8) : (i += 1) {
                        out[bindex * 8 + i] = b & 1 == 1;
                        b >>= 1;
                    }
                }
            } else {
                const U = info.Array.child;
                if (try isFixedSizeObject(U)) {
                    comptime var i = 0;
                    const pitch = @sizeOf(U);
                    inline while (i < out.len) : (i += pitch) {
                        try deserialize(U, serialized[i * pitch .. (i + 1) * pitch], &out[i]);
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
                        try deserialize(U, serialized[start..end], &out[i]);
                    }
                }
            }
        },
        .Bool => out.* = (serialized[0] == 1),
        .Int => {
            const N = @sizeOf(T);
            out.* = std.mem.readInt(T, serialized[0..N], std.builtin.Endian.little);
        },
        .Optional => {
            const index: u8 = serialized[0];
            if (index != 0) {
                var x: info.Optional.child = undefined;
                try deserialize(info.Optional.child, serialized[1..], &x);
                out.* = x;
            } else {
                out.* = null;
            }
        },
        // Data is not copied in this function, copy is therefore
        // the responsibility of the caller.
        .Pointer => out.* = serialized[0..],
        .Struct => {
            // Calculate the number of variable fields in the
            // struct.
            comptime var n_var_fields = 0;
            comptime {
                for (info.Struct.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Int, .Bool => {},
                        else => n_var_fields += 1,
                    }
                }
            }

            var indices: [n_var_fields]u32 = undefined;

            // First pass, read the value of each fixed-size field,
            // and write down the start offset of each variable-sized
            // field.
            comptime var i = 0;
            comptime var variable_field_index = 0;
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool, .Int => {
                        // Direct deserialize
                        try deserialize(field.type, serialized[i .. i + @sizeOf(field.type)], &@field(out.*, field.name));
                        i += @sizeOf(field.type);
                    },
                    else => {
                        try deserialize(u32, serialized[i .. i + 4], &indices[variable_field_index]);
                        i += 4;
                        variable_field_index += 1;
                    },
                }
            }

            // Second pass, deserialize each variable-sized value
            // now that their offset is known.
            comptime var last_index = 0;
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool, .Int => {}, // covered by the previous pass
                    else => {
                        const end = if (last_index == indices.len - 1) serialized.len else indices[last_index + 1];
                        try deserialize(field.type, serialized[indices[last_index]..end], &@field(out.*, field.name));
                        last_index += 1;
                    },
                }
            }
        },
        .Union => {
            // Read the type index
            var union_index: u8 = undefined;
            try deserialize(u8, serialized, &union_index);

            // Use the index to figure out which type must
            // be deserialized.
            inline for (info.Union.fields, 0..) |field, index| {
                if (index == union_index) {
                    // &@field(out.*, field.name) can not be used directly,
                    // because this field type hasn't been activated at this
                    // stage.
                    var data: field.type = undefined;
                    try deserialize(field.type, serialized[1..], &data);
                    out.* = @unionInit(T, field.name, data);
                }
            }
        },
        else => return error.NotImplemented,
    }
}

fn mixInLength(root: [32]u8, length: [32]u8, out: *[32]u8) void {
    var hasher = sha256.init(sha256.Options{});
    hasher.update(root[0..]);
    hasher.update(length[0..]);
    hasher.final(out[0..]);
}

test "mixInLength" {
    var root: [32]u8 = undefined;
    var length: [32]u8 = undefined;
    var expected: [32]u8 = undefined;
    var mixin: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(root[0..], "2279cf111c15f2d594e7a0055e8735e7409e56ed4250735d6d2f2b0d1bcf8297");
    _ = try std.fmt.hexToBytes(length[0..], "deadbeef00000000000000000000000000000000000000000000000000000000");
    _ = try std.fmt.hexToBytes(expected[0..], "0b665dda6e4c269730bc4bbe3e990a69d37fa82892bac5fe055ca4f02a98c900");
    mixInLength(root, length, &mixin);

    try std.testing.expect(std.mem.eql(u8, mixin[0..], expected[0..]));
}

fn mixInSelector(root: [32]u8, comptime selector: usize, out: *[32]u8) void {
    var hasher = sha256.init(sha256.Options{});
    hasher.update(root[0..]);
    var tmp = [_]u8{0} ** 32;
    std.mem.writeInt(@TypeOf(selector), tmp[0..@sizeOf(@TypeOf(selector))], selector, std.builtin.Endian.little);
    hasher.update(tmp[0..]);
    hasher.final(out[0..]);
}

test "mixInSelector" {
    var root: [32]u8 = undefined;
    var expected: [32]u8 = undefined;
    var mixin: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(root[0..], "2279cf111c15f2d594e7a0055e8735e7409e56ed4250735d6d2f2b0d1bcf8297");
    _ = try std.fmt.hexToBytes(expected[0..], "c483cb731afcfe9f2c596698eaca1c4e0dcb4a1136297adef74c31c268966eb5");
    mixInSelector(root, 25, &mixin);

    try std.testing.expect(std.mem.eql(u8, mixin[0..], expected[0..]));
}

/// Calculates the number of leaves needed for the merkelization
/// of this type.
pub fn chunkCount(comptime T: type) usize {
    const info = @typeInfo(T);
    switch (info) {
        .Int, .Bool => return 1,
        .Pointer => return chunkCount(info.Pointer.child),
        // the chunk size of an array depends on its type
        .Array => switch (@typeInfo(info.Array.child)) {
            // Bitvector[N]
            .Bool => return (info.Array.len + 255) / 256,
            // Vector[B,N]
            .Int => return (info.Array.len * @sizeOf(info.Array.child) + 31) / 32,
            // Vector[C,N]
            else => return info.Array.len,
        },
        .Struct => return info.Struct.fields.len,
        else => return error.NotSupported,
    }
}

const chunk = [BYTES_PER_CHUNK]u8;
const zero_chunk: chunk = [_]u8{0} ** BYTES_PER_CHUNK;

fn pack(comptime T: type, values: T, l: *ArrayList(u8)) ![]chunk {
    try serialize(T, values, l);
    const padding_size = (BYTES_PER_CHUNK - l.items.len % BYTES_PER_CHUNK) % BYTES_PER_CHUNK;
    _ = try l.writer().write(zero_chunk[0..padding_size]);
    return std.mem.bytesAsSlice(chunk, l.items);
}

test "pack u32" {
    var expected: [32]u8 = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const out = try pack(u32, 0xdeadbeef, &list);

    _ = try std.fmt.hexToBytes(expected[0..], "efbeadde00000000000000000000000000000000000000000000000000000000");

    try std.testing.expect(std.mem.eql(u8, out[0][0..], expected[0..]));
}

test "pack bool" {
    var expected: [32]u8 = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const out = try pack(bool, true, &list);

    _ = try std.fmt.hexToBytes(expected[0..], "0100000000000000000000000000000000000000000000000000000000000000");

    try std.testing.expect(std.mem.eql(u8, out[0][0..], expected[0..]));
}

test "pack string" {
    var expected: [128]u8 = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const out = try pack([]const u8, "a" ** 100, &list);

    _ = try std.fmt.hexToBytes(expected[0..], "6161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616100000000000000000000000000000000000000000000000000000000");

    try std.testing.expect(expected.len == out.len * out[0].len);
    try std.testing.expect(std.mem.eql(u8, out[0][0..], expected[0..32]));
    try std.testing.expect(std.mem.eql(u8, out[1][0..], expected[32..64]));
    try std.testing.expect(std.mem.eql(u8, out[2][0..], expected[64..96]));
    try std.testing.expect(std.mem.eql(u8, out[3][0..], expected[96..]));
}

fn nextPowOfTwo(len: usize) !usize {
    if (len == 0) {
        return @as(usize, 0);
    }

    // check that the msb isn't set and
    // return an error if it is, as it
    // would overflow.
    if (@clz(len) == 0) {
        return error.OverflowsUSize;
    }

    const n = std.math.log2(std.math.shl(usize, len, 1) - 1);
    return std.math.powi(usize, 2, n);
}

test "next power of 2" {
    var out = try nextPowOfTwo(0b1);
    try std.testing.expect(out == 1);
    out = try nextPowOfTwo(0b10);
    try std.testing.expect(out == 2);
    out = try nextPowOfTwo(0b11);
    try std.testing.expect(out == 4);

    // special cases
    out = try nextPowOfTwo(0);
    try std.testing.expect(out == 0);
    try std.testing.expectError(error.OverflowsUSize, nextPowOfTwo(std.math.maxInt(usize)));
}

// merkleize recursively calculates the root hash of a Merkle tree.
pub fn merkleize(chunks: []chunk, limit: ?usize, out: *[32]u8) anyerror!void {
    // Calculate the number of chunks to be padded, check the limit
    if (limit != null and chunks.len > limit.?) {
        return error.ChunkSizeExceedsLimit;
    }
    const size = try nextPowOfTwo(limit orelse chunks.len);

    // Perform the merkelization
    switch (size) {
        0 => std.mem.copyForwards(u8, out.*[0..], zero_chunk[0..]),
        1 => std.mem.copyForwards(u8, out.*[0..], chunks[0][0..]),
        else => {
            // Merkleize the left side. If the number of chunks
            // isn't enough to fill the entire width, complete
            // with zeroes.
            var digest = sha256.init(sha256.Options{});
            var buf: [32]u8 = undefined;
            const split = if (size / 2 < chunks.len) size / 2 else chunks.len;
            try merkleize(chunks[0..split], size / 2, &buf);
            digest.update(buf[0..]);

            // Merkleize the right side. If the number of chunks only
            // covers the first half, directly input the hashed zero-
            // filled subtrie.
            if (size / 2 < chunks.len) {
                try merkleize(chunks[size / 2 ..], size / 2, &buf);
                digest.update(buf[0..]);
            } else digest.update(hashes_of_zero[size / 2 - 1][0..]);
            digest.final(out);
        },
    }
}

test "merkleize a string" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const chunks = try pack([]const u8, "a" ** 100, &list);
    var out: [32]u8 = undefined;
    try merkleize(chunks, null, &out);
    // Build the expected tree
    const leaf1 = [_]u8{0x61} ** 32; // "0xaaaaa....aa" 32 times
    var leaf2: [32]u8 = [_]u8{0x61} ** 4 ++ [_]u8{0} ** 28;
    var root: [32]u8 = undefined;
    var internal_left: [32]u8 = undefined;
    var internal_right: [32]u8 = undefined;
    var hasher = sha256.init(sha256.Options{});
    hasher.update(leaf1[0..]);
    hasher.update(leaf1[0..]);
    hasher.final(&internal_left);
    hasher = sha256.init(sha256.Options{});
    hasher.update(leaf1[0..]);
    hasher.update(leaf2[0..]);
    hasher.final(&internal_right);
    hasher = sha256.init(sha256.Options{});
    hasher.update(internal_left[0..]);
    hasher.update(internal_right[0..]);
    hasher.final(&root);

    try std.testing.expect(std.mem.eql(u8, out[0..], root[0..]));
}

test "merkleize a boolean" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var chunks = try pack(bool, false, &list);
    var expected = [_]u8{0} ** BYTES_PER_CHUNK;
    var out: [BYTES_PER_CHUNK]u8 = undefined;
    try merkleize(chunks, null, &out);

    try std.testing.expect(std.mem.eql(u8, out[0..], expected[0..]));

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();

    chunks = try pack(bool, true, &list2);
    expected[0] = 1;
    try merkleize(chunks, null, &out);
    try std.testing.expect(std.mem.eql(u8, out[0..], expected[0..]));
}

test "merkleize a bytes16 vector with one element" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const chunks = try pack([16]u8, [_]u8{0xaa} ** 16, &list);
    var expected: [32]u8 = [_]u8{0xaa} ** 16 ++ [_]u8{0x00} ** 16;
    var out: [32]u8 = undefined;
    try merkleize(chunks, null, &out);
    try std.testing.expect(std.mem.eql(u8, out[0..], expected[0..]));
}

fn packBits(bits: []const bool, l: *ArrayList(u8)) ![]chunk {
    var byte: u8 = 0;
    for (bits, 0..) |bit, bitidx| {
        if (bit) {
            byte |= @as(u8, 1) << @as(u3, @truncate(7 - bitidx % 8));
        }
        if (bitidx % 8 == 7 or bitidx == bits.len - 1) {
            try l.append(byte);
            byte = 0;
        }
    }

    // pad the last chunk with 0s
    const padding_size = (BYTES_PER_CHUNK - l.items.len % BYTES_PER_CHUNK) % BYTES_PER_CHUNK;
    _ = try l.writer().write(zero_chunk[0..padding_size]);

    return std.mem.bytesAsSlice(chunk, l.items);
}

pub fn hashTreeRoot(comptime T: type, value: T, out: *[32]u8, allctr: Allocator) !void {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Int, .Bool => {
            var list = ArrayList(u8).init(allctr);
            defer list.deinit();
            const chunks = try pack(T, value, &list);
            try merkleize(chunks, null, out);
        },
        .Array => {
            // Check if the child is a basic type. If so, return
            // the merkle root of its chunked serialization.
            // Otherwise, it is a composite object and the chunks
            // are the merkle roots of its elements.
            switch (@typeInfo(type_info.Array.child)) {
                .Int => {
                    var list = ArrayList(u8).init(allctr);
                    defer list.deinit();
                    const chunks = try pack(T, value, &list);
                    try merkleize(chunks, null, out);
                },
                .Bool => {
                    var list = ArrayList(u8).init(allctr);
                    defer list.deinit();
                    const chunks = try packBits(value[0..], &list);
                    try merkleize(chunks, chunkCount(T), out);
                },
                .Array => {
                    var chunks = ArrayList(chunk).init(allctr);
                    defer chunks.deinit();
                    var tmp: chunk = undefined;
                    for (value) |item| {
                        try hashTreeRoot(@TypeOf(item), item, &tmp, allctr);
                        try chunks.append(tmp);
                    }
                    try merkleize(chunks.items, null, out);
                },
                else => return error.NotSupported,
            }
        },
        .Pointer => {
            switch (type_info.Pointer.size) {
                .One => hashTreeRoot(type_info.Pointer.child, value.*, out, allctr),
                .Slice => {
                    switch (@typeInfo(type_info.Pointer.child)) {
                        .Int => {
                            var list = ArrayList(u8).init(allctr);
                            defer list.deinit();
                            const chunks = try pack(T, value, &list);
                            merkleize(chunks, null, out);
                        },
                        else => return error.UnSupportedPointerType,
                    }
                },
                else => return error.UnSupportedPointerType,
            }
        },
        .Struct => {
            var chunks = ArrayList(chunk).init(allctr);
            defer chunks.deinit();
            var tmp: chunk = undefined;
            inline for (type_info.Struct.fields) |f| {
                try hashTreeRoot(f.type, @field(value, f.name), &tmp, allctr);
                try chunks.append(tmp);
            }
            try merkleize(chunks.items, null, out);
        },
        // An optional is a union with `None` as first value.
        .Optional => if (value != null) {
            var tmp: chunk = undefined;
            try hashTreeRoot(type_info.Optional.child, value.?, &tmp, allctr);
            mixInSelector(tmp, 1, out);
        } else {
            mixInSelector(zero_chunk, 0, out);
        },
        .Union => {
            if (type_info.Union.tag_type == null) {
                return error.UnionIsNotTagged;
            }
            inline for (type_info.Union.fields, 0..) |f, index| {
                if (@intFromEnum(value) == index) {
                    var tmp: chunk = undefined;
                    try hashTreeRoot(f.type, @field(value, f.name), &tmp, allctr);
                    mixInSelector(tmp, index, out);
                }
            }
        },
        else => return error.NotSupported,
    }
}

// used at comptime to generate a bitvector from a byte vector
fn bytesToBits(comptime N: usize, src: [N]u8) [N * 8]bool {
    var bitvector: [N * 8]bool = undefined;
    for (src, 0..) |byte, idx| {
        var i = 0;
        while (i < 8) : (i += 1) {
            bitvector[i + idx * 8] = ((byte >> (7 - i)) & 1) == 1;
        }
    }
    return bitvector;
}
