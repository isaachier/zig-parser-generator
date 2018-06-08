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
    try parser.parse();
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
    const ErrorSet = error {
        InvalidRuleStart,
    };

    tokenizer: Tokenizer,
    rule_set: grammar.RuleSet,
    token: Token,

    pub fn init(alloc: *Allocator, in: *FileInStream) Parser {
        return Parser{
            .tokenizer = Tokenizer.init(alloc, in),
            .rule_set = grammar.RuleSet.init(alloc),
            .token = Token.init(alloc),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.tokenizer.deinit();
        self.rule_set.deinit();
        self.token.deinit();
    }

    fn consume(self: *Parser) !void {
        var next = try self.tokenizer.nextToken();
        self.token.deinit();
        self.token = next;
        std.debug.warn("test\n");
    }

    pub fn parse(self: *Parser) !void {
        try self.consume();
        while (self.token.kind != Token.Kind.EndOfFile) {
            std.debug.assert(self.token.kind != Token.Kind.Invalid);
            try self.parseRule();
        }
    }

    fn parseRule(self: *Parser) !void {
        if (self.token.kind != Token.Kind.Symbol) {
            return Parser.ErrorSet.InvalidRuleStart;
        }
        std.debug.warn("rule name: {}\n", self.token.buffer.toSliceConst());
        var rule = try self.rule_set.put(self.token.buffer.toSliceConst());
        // TODO
    }
};

test "parse input" {
    try parseInputFile(std.debug.global_allocator, "grammar-test.txt");
}
