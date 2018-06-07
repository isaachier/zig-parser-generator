const std = @import("std");
const cstr = std.cstr;
const io = std.io;
const mem = std.mem;
const os = std.os;
const Allocator = mem.Allocator;
const Buffer = std.Buffer;
const File = os.File;
const FileInStream = io.FileInStream;

const grammar = @import("grammar.zig");

pub fn parseInputFile(allocator: *Allocator, path: []const u8) !void {
    var file = try File.openRead(allocator, path);
    defer file.close();
    var adapter = FileInStream.init(&file);
    var parser = Parser.init(allocator, &adapter);
    defer parser.deinit();
    var token = try parser.tokenizer.nextToken();
    while (token.len() > 0) : (token = try parser.tokenizer.nextToken()) {
        std.debug.warn("token: \"{}\"\n", token.toSliceConst());
        token.deinit();
    }
}

const Tokenizer = struct {
    in: *FileInStream,
    lookahead: Buffer,

    pub fn init(alloc: *Allocator, in: *FileInStream) Tokenizer {
        return Tokenizer{
            .in = in,
            .lookahead = Buffer.initNull(alloc),
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.lookahead.deinit();
    }

    fn allocator(self: *Tokenizer) *Allocator {
        return self.lookahead.list.allocator;
    }

    pub fn nextToken(self: *Tokenizer) !Buffer {
        if (!self.lookahead.isNull()) {
            std.debug.assert(self.lookahead.len() > 0);
            var token = try Buffer.fromOwnedSlice(
                self.allocator(),
                self.lookahead.toOwnedSlice(),
            );
            self.lookahead.deinit();
            self.lookahead = Buffer.initNull(self.allocator());
            return token;
        }

        var token = try Buffer.init(self.allocator(), "");
        while (true) {
            var byte: u8 = self.in.stream.readByte() catch return token;

            if (byte == ' ') {
                return token;
            }

            if (mem.indexOfScalar(u8, cstr.line_sep, byte) != null) {
                std.debug.assert(self.lookahead.isNull());
                try self.lookahead.resize(1);
                self.lookahead.list.items[0] = byte;
                return token;
            }

            try token.appendByte(byte);
        }
    }
};

const Parser = struct {
    tokenizer: Tokenizer,
    rule_set: grammar.RuleSet,

    pub fn init(alloc: *Allocator, in: *FileInStream) Parser {
        return Parser{
            .tokenizer = Tokenizer.init(alloc, in),
            .rule_set = grammar.RuleSet.init(alloc),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.tokenizer.deinit();
        self.rule_set.deinit();
    }

    pub fn parse(self: *Parser) !grammar.RuleSet {
        // TODO
        return error.InvalidChar;
    }
};

test "parse input" {
    try parseInputFile(std.debug.global_allocator, "grammar-test.txt");
}
