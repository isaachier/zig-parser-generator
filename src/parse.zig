const std = @import("std");

const grammar = @import("grammar.zig");

pub const Token = struct {
    pub const Id = enum {
        Symbol,
        String,
        Equal,
        Or,
        EndOfRule,
        Invalid,
    };

    id: Id,
    pos: usize,
    len: usize,

    pub fn init(pos: usize, len: usize) Token {
        return Token{
            .id = Id.Invalid,
            .pos = pos,
            .len = len,
        };
    }

    pub fn slice(self: *const Token, input: []const u8) []const u8 {
        std.debug.assert(self.pos + self.len <= input.len);
        return input[self.pos .. self.pos + self.len];
    }
};

pub const TokenStream = struct {
    input: []const u8,
    pos: usize,

    pub fn init(input: []const u8) TokenStream {
        return TokenStream{
            .input = input,
            .pos = 0,
        };
    }

    fn isSpace(byte: u8) bool {
        return byte == ' ' or std.mem.indexOfScalar(u8, std.cstr.line_sep, byte) != null;
    }

    fn isReserved(byte: u8) bool {
        const reserved_letters = ";|()[]{}";
        return std.mem.indexOfScalar(u8, reserved_letters, byte) != null;
    }

    fn skipSpace(self: *TokenStream) void {
        while (self.pos < self.input.len) : (self.pos += 1) {
            const byte = self.input[self.pos];
            if (!isSpace(byte)) {
                break;
            }
        }
    }

    pub fn next(self: *TokenStream) Token {
        self.skipSpace();

        var token = Token.init(self.pos, 0);
        while (self.pos < self.input.len) {
            const byte = self.input[self.pos];
            if (isSpace(byte)) {
                break;
            }
            if (isReserved(byte) and token.pos < self.pos) {
                break;
            }
            self.pos += 1;
        }

        token.len = self.pos - token.pos;
        switch (token.len) {
            1 => {
                token.id = switch (self.input[token.pos]) {
                    '|' => Token.Id.Or,
                    '=' => Token.Id.Equal,
                    ';' => Token.Id.EndOfRule,
                    else => Token.Id.Symbol,
                };
            },
            else => {
                if (token.len > 0) {
                    token.id = switch (self.input[token.pos]) {
                        '"' => Token.Id.String,
                        else => Token.Id.Symbol,
                    };
                }
            },
        }
        return token;
    }
};

pub const Parser = struct {
    const ErrorSet = error{
        InvalidRuleStart,
        InvalidToken,
    };

    allocator: *std.mem.Allocator,
    token_stream: TokenStream,
    token: Token,

    pub fn init(allocator: *std.mem.Allocator, input: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .token_stream = TokenStream.init(input),
            .token = Token.init(0, 0),
        };
    }

    fn consume(self: *Parser) void {
        self.token = self.token_stream.next();
    }

    pub fn parse(self: *Parser) !grammar.RuleSet {
        var rule_set = grammar.RuleSet.init(self.allocator);
        errdefer rule_set.deinit();
        self.consume();
        while (self.token.id != Token.Id.Invalid) {
            var rule = try self.parseRule(rule_set.prod_list.len);
            errdefer rule.deinit();
            try rule_set.put(&rule);
        }
        return rule_set;
    }

    fn parseRule(self: *Parser, prod_list_len: usize) !grammar.Rule {
        if (self.token.id != Token.Id.Symbol) {
            return Parser.ErrorSet.InvalidRuleStart;
        }
        const name = self.token.slice(self.token_stream.input);
        const name_copy = try std.mem.dupe(self.allocator, u8, name);
        errdefer self.allocator.free(name_copy);

        self.consume();
        if (self.token.id != Token.Id.Equal) {
            return Parser.ErrorSet.InvalidToken;
        }
        self.consume();

        var prods = std.ArrayList(grammar.Production).init(self.allocator);
        defer prods.deinit();
        errdefer {
            for (prods.toSlice()) |*prod| {
                prod.deinit();
            }
            prods.deinit();
        }
        while (self.token.id != Token.Id.EndOfRule) {
            var prod = try self.parseProduction(prod_list_len + prods.len, name_copy);
            errdefer prod.deinit();
            try prods.append(prod);
        }
        self.consume();
        return grammar.Rule.init(self.allocator, name_copy, prods.toOwnedSlice());
    }

    fn parseProduction(self: *Parser, prod_id: usize, rule_name: []const u8) !grammar.Production {
        var symbols = std.ArrayList([]const u8).init(self.allocator);
        errdefer symbols.deinit();
        while (true) {
            switch (self.token.id) {
                Token.Id.Symbol, Token.Id.String => {
                    try symbols.append(self.token.slice(self.token_stream.input));
                    self.consume();
                },
                Token.Id.Or, Token.Id.EndOfRule, Token.Id.Invalid => {
                    if (self.token.id == Token.Id.Or) {
                        self.consume();
                    }
                    return grammar.Production.init(
                        self.allocator,
                        prod_id,
                        rule_name,
                        symbols.toOwnedSlice(),
                    );
                },
                else => return ErrorSet.InvalidToken,
            }
        }
    }
};
