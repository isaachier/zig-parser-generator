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
    while (token.kind != Token.Kind.EndOfFile) {
        std.debug.warn("token: {} \"{}\"\n", @tagName(token.kind), if (!token.buffer.isNull() and token.buffer.len() > 0) token.buffer.toSliceConst() else "");
        token.deinit();
        token = try parser.tokenizer.nextToken();
    }
    token.deinit();
}

const Token = struct {
    pub const Kind = enum {
        Symbol,
        String,
        Equal,
        Or,
        EndOfRule,
        EndOfFile,
        Invalid,
    };

    kind: Kind,
    buffer: Buffer,

    pub fn init(allocator: *Allocator) Token {
        return Token{
            .kind = Kind.Invalid,
            .buffer = Buffer.initNull(allocator),
        };
    }

    pub fn deinit(self: *Token) void {
        self.buffer.deinit();
    }

    pub fn setBuffer(self: *Token, buffer: *Buffer) !void {
        self.buffer = try Buffer.fromOwnedSlice(self.buffer.list.allocator, buffer.toOwnedSlice());
    }
};

const Tokenizer = struct {
    const ErrorSet = error {
        OutOfMemory,
    };

    in: *FileInStream,
    lookahead: Token,

    pub fn init(alloc: *Allocator, in: *FileInStream) Tokenizer {
        return Tokenizer{
            .in = in,
            .lookahead = Token.init(alloc),
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.lookahead.deinit();
    }

    fn allocator(self: *Tokenizer) *Allocator {
        return self.lookahead.buffer.list.allocator;
    }

    pub fn nextToken(self: *Tokenizer) Tokenizer.ErrorSet!Token {
        if (self.lookahead.kind != Token.Kind.Invalid) {
            var token = self.lookahead;
            self.lookahead = Token.init(self.allocator());
            return token;
        }

        var token = Token.init(self.allocator());
        try token.buffer.resize(0);
        loop: {
            while (true) {
                var byte: u8 = self.in.stream.readByte() catch {
                    if (token.buffer.len() > 0) {
                        break :loop;
                    }

                    token.deinit();
                    token = Token.init(self.allocator());
                    token.kind = Token.Kind.EndOfFile;
                    break :loop;
                };

                if (byte == ' ') {
                    break :loop;
                }

                if (mem.indexOfScalar(u8, cstr.line_sep, byte) != null) {
                    self.lookahead.kind = Token.Kind.EndOfRule;
                    break :loop;
                }

                try token.buffer.appendByte(byte);
            }
        }

        if (token.kind == Token.Kind.Invalid) {
            return switch (token.buffer.len()) {
                1 => blk: {
                    token.kind = switch (token.buffer.list.items[0]) {
                        '"' => Token.Kind.String,
                        '|' => Token.Kind.Or,
                        '=' => Token.Kind.Equal,
                        else => Token.Kind.Symbol,
                    };
                    break :blk token;
                },
                0 => self.nextToken(),
                else => blk: {
                    token.kind = Token.Kind.Symbol;
                    break :blk token;
                },
            };
        }

        return token;
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
