const std = @import("std");
const cstr = std.cstr;
const debug = std.debug;
const io = std.io;
const mem = std.mem;
const os = std.os;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

const Production = struct {
    allocator: *Allocator,
    id: usize,
    symbols: [][]const u8,

    pub fn init(allocator: *Allocator, id: usize, symbols: [][]const u8) Production {
        return Production{
            .allocator = allocator,
            .id = id,
            .symbols = symbols,
        };
    }

    pub fn deinit(self: *Production) void {
        self.allocator.free(self.symbols);
    }
};

const RuleSet = struct {
    const RuleMap = HashMap([]const u8, []Production, mem.hash_slice_u8, mem.eql_slice_u8);

    const ErrorSet = error {
        RuleDoesNotExist,
    };

    start_symbol: []const u8,
    map: RuleMap,

    pub fn init(allocator: *Allocator) RuleSet {
        return RuleSet{
            .start_symbol = "",
            .map = RuleMap.init(allocator),
        };
    }

    pub fn deinit(self: *RuleSet) void {
        var it = self.map.iterator();
        while (it.next()) |rule| {
            self.map.allocator.free(rule.key);
            for (rule.value) |_, i| {
                rule.value[i].deinit();
            }
            self.map.allocator.free(rule.value);
        }
        self.map.deinit();
    }

    pub fn put(self: *RuleSet, name: []const u8, productions: []Production) !void {
        if (self.map.contains(name)) {
            return;
        }
        if (self.start_symbol.len == 0) {
            self.start_symbol = name;
        }
        const old_entry = try self.map.put(name, productions);
        debug.assert(old_entry == null);
    }

    pub fn get(self: *const RuleSet, name: []const u8) ![]const Production {
        var rule_entry = self.map.get(name);
        if (rule_entry == null) {
            return RuleSet.ErrorSet.RuleDoesNotExist;
        }
        return rule_entry.?.value;
    }
};

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
        debug.assert(self.pos + self.len <= input.len);
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

    fn isReserved(byte: u8) bool {
        const reserved_letters = ";|()[]{}";
        return mem.indexOfScalar(u8, reserved_letters, byte) != null;
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

const Parser = struct {
    const ErrorSet = error {
        InvalidRuleStart,
        InvalidToken,
    };

    token_stream: TokenStream,
    token: Token,
    rule_set: RuleSet,
    rule_counter: usize,

    pub fn init(allocator: *Allocator, input: []const u8) Parser {
        return Parser{
            .token_stream = TokenStream.init(input),
            .token = Token.init(0, 0),
            .rule_set = RuleSet.init(allocator),
            .rule_counter = 0,
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
        while (self.token.id != Token.Id.Invalid) : (self.consume()) {
            try self.parseRule();
        }
    }

    fn parseRule(self: *Parser) !void {
        if (self.token.id != Token.Id.Symbol) {
            return Parser.ErrorSet.InvalidRuleStart;
        }
        const name = self.token.slice(self.token_stream.input);
        var productions = ArrayList(Production).init(self.rule_set.map.allocator);
        defer productions.deinit();
        var symbols = ArrayList([]const u8).init(self.rule_set.map.allocator);

        self.consume();
        if (self.token.id != Token.Id.Equal) {
            return Parser.ErrorSet.InvalidToken;
        }

        self.consume();
        while (true) : (self.consume()) {
            switch (self.token.id) {
                Token.Id.Symbol, Token.Id.String =>
                    try symbols.append(self.token.slice(self.token_stream.input)),
                Token.Id.Or, Token.Id.EndOfRule => {
                    {
                        const symbols_slice = symbols.toOwnedSlice();
                        errdefer self.rule_set.map.allocator.free(symbols_slice);
                        try productions.append(Production{
                            .allocator = self.rule_set.map.allocator,
                            .id = self.rule_counter,
                            .symbols = symbols_slice,
                        });
                        debug.assert(symbols_slice.len == productions.at(productions.len - 1).symbols.len);
                        self.rule_counter += 1;
                    }
                    if (self.token.id == Token.Id.EndOfRule) {
                        const productions_slice = productions.toOwnedSlice();
                        errdefer self.rule_set.map.allocator.free(productions_slice);
                        try self.rule_set.put(name, productions_slice);
                        return;
                    }
                },
                Token.Id.Invalid => return,
                else => return ErrorSet.InvalidToken,
            }
        }
    }
};

fn hashUSize(x: usize) u32 {
    const array = []usize{ x };
    const slice = array[0..];
    return mem.hash_slice_u8(@sliceToBytes(slice));
}

fn eqlUSize(lhs: usize, rhs: usize) bool {
    return lhs == rhs;
}

const Item = struct {
    allocator: *Allocator,
    production: *const Production,
    marker: usize,

    pub fn init(allocator: *Allocator, production: *const Production, marker: usize) Item {
        debug.assert(marker <= production.symbols.len);
        return Item{
            .allocator = allocator,
            .production = production,
            .marker = marker,
        };
    }

    const VisitedSet = HashMap(usize, bool, hashUSize, eqlUSize);

    const ErrorSet = error {
        OutOfMemory,
    };

    pub fn findClosure(self: *const Item, rule_set: *const RuleSet) ![]Item {
        var items = ArrayList(Item).init(self.allocator);
        var visited = VisitedSet.init(self.allocator);
        defer visited.deinit();
        try self.findClosureHelper(rule_set, &items, &visited);
        return items.toOwnedSlice();
    }

    fn findClosureHelper(self: *const Item,
                         rule_set: *const RuleSet,
                         items: *ArrayList(Item),
                         visited: *VisitedSet) ErrorSet!void {
        if (visited.contains(self.production.id)) {
            return;
        }

        try items.append(self.*);
        const old_entry = try visited.put(self.production.id, true);
        debug.assert(old_entry == null);

        debug.assert(self.marker <= self.production.symbols.len);
        if (self.marker == self.production.symbols.len) {
            return;
        }

        const marked_symbol = self.production.symbols[self.marker];
        const marked_productions = rule_set.get(marked_symbol) catch []const Production{};

        if (marked_productions.len == 0) {
            return;
        }

        for (marked_productions) |marked_production| {
            const item = Item.init(self.allocator, marked_production, 0);
            try item.findClosureHelper(rule_set, items, visited);
        }
    }
};

test "parse input" {
    const input =
    \\ S = E;
    \\ E = E "*" B | E "+" B | B | "0" | "1";
    \\
    ;
    var parser = Parser.init(debug.global_allocator, input);
    defer parser.deinit();
    try parser.parse();
    const productions = try parser.rule_set.get("E");
    debug.assert(productions.len == 5);
    for (productions) |prod| {
        debug.warn("{} =", prod.id);
        for (prod.symbols) |symbol| {
            debug.warn(" {}", symbol);
        }
        debug.warn("\n");
    }
    debug.assert(mem.eql_slice_u8(parser.rule_set.start_symbol, "S"));
    const start_productions = try parser.rule_set.get(parser.rule_set.start_symbol);
    debug.assert(start_productions.len == 1);
}
