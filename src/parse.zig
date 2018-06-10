const std = @import("std");
const cstr = std.cstr;
const debug = std.debug;
const io = std.io;
const mem = std.mem;
const os = std.os;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const File = os.File;
const FileInStream = io.FileInStream;
const HashMap = std.HashMap;

const Rule = struct {
    name: []const u8,
    tokens: ArrayList(Token),

    pub fn init(allocator: *Allocator, name: []const u8) Rule {
        return Rule{
            .name = name,
            .tokens = ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *Rule) void {
        self.tokens.deinit();
    }

    pub fn append(self: *Rule, token: *const Token) !void {
        try self.tokens.append(token);
    }
};

const RuleSet = struct {
    const RuleMap = HashMap([]const u8, ArrayList(Rule), mem.hash_slice_u8, mem.eql_slice_u8);

    const ErrorSet = error {
        RuleDoesNotExist,
    };

    map: RuleMap,

    pub fn init(allocator: *Allocator) RuleSet {
        return RuleSet{
            .map = RuleMap.init(allocator),
        };
    }

    pub fn deinit(self: *RuleSet) void {
        var it = self.map.iterator();
        while (it.next()) |next| {
            next.value.deinit();
        }
        self.map.deinit();
    }

    pub fn put(self: *RuleSet, name: []const u8) !*ArrayList(Rule) {
        _ = try self.map.put(name, ArrayList(Rule).init(self.map.allocator));
        var entry = self.map.get(name).?;
        return &entry.value;
    }

    pub fn get(self: *RuleSet, name: []const u8) !*ArrayList(Rule) {
        var rule_entry = self.map.get(name);
        if (rule_entry == null) {
            return RuleSet.ErrorSet.RuleDoesNotExist;
        }
        return &(rule_entry.?).value;
    }
};

test "rule set initialization" {
    var rule_set = RuleSet.init(std.debug.global_allocator);
    defer rule_set.deinit();

    var rules = try rule_set.put("S");
    try rules.append(Rule.init(rule_set.map.allocator, "S"));
    var rule = &rules.items[0];
    try rule.append(Token.init(0, 0));
    try rule.append(Token.init(0, 0));
}

const Token = struct {
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
        return input[self.pos .. self.pos + self.len];
    }
};

const TokenStream = struct {
    input: []const u8,
    pos: usize,

    pub fn init(input: []const u8) TokenStream {
        return TokenStream{
            .input = input,
            .pos = 0,
        };
    }

    fn isSpace(byte: u8) bool {
        return byte == ' ' or mem.indexOfScalar(u8, cstr.line_sep, byte) != null;
    }

    fn skipSpace(self: *TokenStream) void {
        while (self.pos < self.input.len) {
            const byte = self.input[self.pos];
            if (!isSpace(byte)) {
                break;
            }
            self.pos += 1;
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

const Parser = struct {
    const ErrorSet = error {
        InvalidRuleStart,
        InvalidToken,
    };

    token_stream: TokenStream,
    token: Token,
    rule_set: RuleSet,

    pub fn init(allocator: *Allocator, input: []const u8) Parser {
        return Parser{
            .token_stream = TokenStream.init(input),
            .token = Token.init(0, 0),
            .rule_set = RuleSet.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.rule_set.deinit();
    }

    fn consume(self: *Parser) void {
        self.token = self.token_stream.next();
    }

    pub fn parse(self: *Parser) !void {
        self.consume();
        while (self.token.id != Token.Id.Invalid) {
            try self.parseRule();
        }
    }

    fn parseRule(self: *Parser) !void {
        if (self.token.id != Token.Id.Symbol) {
            return Parser.ErrorSet.InvalidRuleStart;
        }
        const name = self.token.slice(self.token_stream.input);
        var rules = try self.rule_set.put(name);
        try rules.append(Rule.init(self.rule_set.map.allocator, name));
        var rule = &rules.items[0];

        self.consume();
        if (self.token.id != Token.Id.Equal) {
            return Parser.ErrorSet.InvalidToken;
        }

        self.consume();
        while (true) : (self.consume()) {
            switch (self.token.id) {
                Token.Id.EndOfRule => return,
                Token.Id.Invalid => return,
                Token.Id.Symbol => try rule.append(self.token),
                Token.Id.String => try rule.append(self.token),
                Token.Id.Or => {
                    try rules.append(Rule.init(self.rule_set.map.allocator, name));
                    rule = &rules.items[rules.len - 1];
                },
                else => return ErrorSet.InvalidToken,
            }
        }
    }
};

test "parse input" {
    const input =
    \\ E = E "*" B | E "+" B | B | "0" | "1";
    \\
    ;
    var parser = Parser.init(debug.global_allocator, input);
    defer parser.deinit();
    try parser.parse();
    const rules = try parser.rule_set.get("E");
    debug.assert(rules.len == 5);
}
