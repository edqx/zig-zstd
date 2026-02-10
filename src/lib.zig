const std = @import("std");
const c = @import("c");

pub const DEFAULT_COMPRESSION_LEVEL = 3;
pub const MIN_COMPRESSION_LEVEL = -131072;
pub const MAX_COMPRESSION_LEVEL = 22;

// Code based on https://github.com/alichraghi/zstd.zig/blob/ddd1fe82a5157bb65bc815a552bbfb01bb502acf/src/error.zig#L3
pub const Error = error{
    Generic,
    UnknownPrefix,
    UnsupportedVersion,
    UnsupportedFrameParameter,
    TooLargeFrameParameterWindow,
    CorruptionDetected,
    WrongChecksum,
    CorruptedDictionary,
    WrongDictionary,
    DictionaryCreationFailed,
    UnsupportedParameter,
    OutOfBoundsParameter,
    TooLargeTableLog,
    TooLargeMaxSymbolValue,
    TooSmallMaxSymbolValue,
    WrongStage,
    InitMissing,
    OutOfMemory,
    TooSmallWorkspace,
    TooSmallDestSize,
    WrongSrcSize,
    NullDestBuffer,
    NoForwardProgressDestFull,
    NoForwardProgressInputEmpty,
    TooLargeFrameIndex,
    SeekableIO,
    WrongDestBuffer,
    WrongSrcBuffer,
    SequenceProducerFailed,
    InvalidExternalSequences,
    MaxCode,
    UnknownError,
};

pub inline fn isError(code: usize) bool {
    return c.ZSTD_isError(code) != 0;
}

pub fn checkError(code: usize) Error!usize {
    if (isError(code))
        switch (c.ZSTD_getErrorCode(code)) {
            1 => return error.Generic,
            10 => return error.UnknownPrefix,
            12 => return error.UnsupportedVersion,
            14 => return error.UnsupportedFrameParameter,
            16 => return error.TooLargeFrameParameterWindow,
            20 => return error.CorruptionDetected,
            22 => return error.WrongChecksum,
            30 => return error.CorruptedDictionary,
            32 => return error.WrongDictionary,
            34 => return error.DictionaryCreationFailed,
            40 => return error.UnsupportedParameter,
            42 => return error.OutOfBoundsParameter,
            44 => return error.TooLargeTableLog,
            46 => return error.TooLargeMaxSymbolValue,
            48 => return error.TooSmallMaxSymbolValue,
            60 => return error.WrongStage,
            62 => return error.InitMissing,
            64 => return error.OutOfMemory,
            66 => return error.TooSmallWorkspace,
            70 => return error.TooSmallDestSize,
            72 => return error.WrongSrcSize,
            74 => return error.NullDestBuffer,
            80 => return error.NoForwardProgressDestFull,
            82 => return error.NoForwardProgressInputEmpty,
            // following error codes are __NOT STABLE__, they can be removed or changed in future versions
            100 => return error.TooLargeFrameIndex,
            102 => return error.SeekableIO,
            104 => return error.WrongDestBuffer,
            105 => return error.WrongSrcBuffer,
            106 => return error.SequenceProducerFailed,
            107 => return error.InvalidExternalSequences,
            120 => return error.MaxCode,
            else => return error.UnknownError,
        };
    return code;
}

pub const Compress = struct {
    inner: *c.ZSTD_CStream,

    output: *std.Io.Writer,
    writer: std.Io.Writer,

    pub fn init(output: *std.Io.Writer, out_buffer: []u8, level: i32) Error!Compress {
        const c_stream = c.ZSTD_createCStream();
        if (c_stream == null) return error.OutOfMemory;
        
        _ = try checkError(c.ZSTD_initCStream(c_stream, level));

        return .{
            .inner = c_stream.?,
            .output = output,
            .writer = .{
                .buffer = out_buffer,
                .end = 0,
                .vtable = &.{
                    .drain = &drain,
                },
            },
        };
    }
    
    pub fn deinit(compress: *Compress) void {
        _ = c.ZSTD_freeCStream(compress.inner);
        compress.* = undefined;
    }
    
    fn writeImpl(compress: *Compress, slice: []const u8) std.Io.Writer.Error!usize {
        const dest = try compress.output.writableSliceGreedy(1);
        const actual_writable = slice[0..@min(slice.len, dest.len)];
        
        var in_buffer: c.ZSTD_inBuffer_s = .{
            .src = actual_writable.ptr,
            .size = actual_writable.len,
            .pos = 0,
        };
        
        var out_buffer: c.ZSTD_outBuffer_s = .{
            .dst = dest.ptr,
            .size = dest.len,
            .pos = 0,
        };

        _ = checkError(c.ZSTD_compressStream(compress.inner, &out_buffer, &in_buffer)) catch return error.WriteFailed;

        compress.output.advance(out_buffer.pos);
        _ = compress.writer.consume(in_buffer.pos);
        return in_buffer.pos;
    }
    
    pub fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const compress: *Compress = @fieldParentPtr("writer", writer);
        
        const pattern = data[data.len - 1];
        
        var total: usize = 0;
        
        const n1 = try compress.writeImpl(writer.buffered());
        total += n1;
        if (n1 < writer.buffered().len) return total;

        for (data[0..data.len - 1]) |slice| {
            const n2 = try compress.writeImpl(slice);
            total += n2;
            if (n2 < slice.len) return total;
        }
        for (0..splat) |_| {
            const n3 = try compress.writeImpl(pattern);
            total += n3;
            if (n3 < pattern.len) return total;
        }

        return total;
    }
    
    pub fn end(compress: *Compress) std.Io.Writer.Error!void {
        try compress.writer.defaultFlush();

        while (true) {
            const dest = try compress.output.writableSliceGreedy(1);
            var out_buffer: c.ZSTD_outBuffer_s = .{
                .dst = dest.ptr,
                .size = dest.len,
                .pos = 0,
            };
            const num2 = checkError(c.ZSTD_endStream(compress.inner, &out_buffer)) catch return error.WriteFailed;
            compress.output.advance(out_buffer.pos);
            if (num2 == 0) break;
        }
        
        try compress.output.flush();
    }
};

test Compress {
    const gpa = std.testing.allocator;

    const data = "BARNEY BARNEY BARNEY BARNEY";
    
    var compressed_writer: std.Io.Writer.Allocating = .init(gpa);
    defer compressed_writer.deinit();

    var buffer: [1]u8 = undefined;

    var compress: Compress = try .init(&compressed_writer.writer, &buffer, 1);
    defer compress.deinit();
    
    try compress.writer.writeAll(data);
    try compress.writer.flush();

    try compress.end();

    try std.testing.expectEqualSlices(u8, &.{ 40, 181, 47, 253, 0, 72, 109, 0, 0, 56, 66, 65, 82, 78, 69, 89, 32, 1, 0, 162, 139, 17 }, compressed_writer.written());
}