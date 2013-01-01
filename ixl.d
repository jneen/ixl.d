import std.stdio;
import std.ascii;
import std.string;

int main(string[] argv) {
  if (argv.length > 1 && argv[1] == "--test") return 0;

  string input;
  readf("%s", &input);

  writeln(parseIxl(input));
  return 0;
}

class Scanner {
  string s;
  size_t pos = 0;

  this(in string s) { this.s = s; }

  char peek() { return peek(0); }

  char peek(size_t n) {
    return s[n + pos];
  }

  bool test(char ch) { return test(0, ch); }
  bool test(size_t i, char ch) {
    return hasMore() && peek(i) == ch;
  }

  bool test(string st) { return test(0, st); }
  bool test(size_t i, string st) {
    return hasMore() && inPattern(peek(i), st);
  }

  string advance() { return advance(1); }

  string advance(size_t n) {
    assert(pos <= s.length - n);

    pos += n;
    return s[ pos - n .. pos ];
  }

  void expect(char ch, string msg) {
    if (!test(ch)) {
      parseError(format("expected %s", msg));
    }

    advance();
  }

  void parseError(string message) {
    throw new Error(message);
  }

  string pre() {
    return s[0 .. pos];
  }

  string post() {
    return s[pos .. $];
  }

  bool hasMore() { return hasMore(1); }

  bool hasMore(size_t n) {
    return pos <= s.length - n;
  }

  string consume(string pattern) {
    size_t oldPos = pos;
    while (hasMore()) {
      if (inPattern(peek(), pattern)) {
        pos++;
      }
      else {
        return s[oldPos .. pos];
      }
    }

    return s[oldPos .. $];
  }

  string consumeNot(string pattern) {
    size_t oldPos = pos;
    while (hasMore()) {
      if (!inPattern(peek(), pattern)) {
        pos++;
      }
      else {
        return s[oldPos .. pos];
      }
    }

    return s[oldPos .. $];
  }

  string inspect() {
    return format("#<Scanner [%s] [%s]", pre(), post());
  }

  unittest {
    auto s = new Scanner("  foo\nbar");
    assert(s.pre() == "");
    assert(s.post() == "  foo\nbar");

    auto payload = s.consume(whitespace);
    assert(s.pre() == "  ");
    assert(s.post() == "foo\nbar");
    assert(payload == "  ");

    payload = s.consume(whitespace);
    assert(s.pre() == "  ");
    assert(s.post() == "foo\nbar");
    assert(payload == "");

    payload = s.consumeNot(whitespace);
    assert(s.pre() == "  foo");
    assert(s.post() == "\nbar");
    assert(payload == "foo");

    payload = s.advance();
    assert(s.pre() == "  foo\n");
    assert(s.post() == "bar");
    assert(payload == "\n");
  }
}

class IxlScanner : Scanner {
  enum spaces = " \t";
  enum wordTerminators = " \t\r\n#];";

  this(in string s) { super(s); }

  // parses a bareword or a {}-delimited balanced string.
  string parseString() {
    if (!test('{')) return consumeNot(wordTerminators);

    int braceCount = 0;
    size_t marker = this.pos + 1;

    while (hasMore()) {
      switch(peek()) {
        case '{':
          advance();
          ++braceCount;
          break;

        case '}':
          advance();
          --braceCount;
          if (braceCount == 0) goto end;
          break;

        case '\\':
          if (!hasMore(2)) throw new Error("Unexpected EOF!");
          advance(2);
          break;

        default:
          consumeNot("{}\\");
          break;
      }
    }

    throw new Error("unexpected EOF");

end:
    // TODO: unescape \{ and \}
    return this.s[marker .. pos-1];
  }

  unittest {
    string parsed = (new IxlScanner("{asdf}")).parseString();
    assert(parsed == "asdf");

    parsed = (new IxlScanner("{a{{s{}d{f}}}}")).parseString();
    assert(parsed == "a{{s{}d{f}}}");
  }

  class Block {
    Command[] commands;
  }

  Block parseBlock() {
    auto block = new Block();

    expect('[', "a block");

    parseWhitespace();
    while(hasMore()) {
      if (peek() == ']') return block;

      block.commands ~= parseCommand();
    }

    parseError("unexpected EOF");

    // won't get here :(
    return block;
  }

  unittest {
    auto n = (new IxlScanner("[]")).parseBlock();
    assert(n.commands.length == 0);

    n = (new IxlScanner("[foo --bar]")).parseBlock();
    assert(n.commands.length == 1);
    assert(n.commands[0].call !is null);
    assert(n.commands[0].call.type == Term.TermType.STRING);
    assert(n.commands[0].call.string_ == "foo");
    assert("bar" in n.commands[0].flags);
  }

  class Term {
    enum TermType { BLOCK, VARIABLE, STRING };

    TermType type;
    union {
      Block block;
      string variable;
      string string_;
    }
  }

  Term parseTerm() {
    auto term = new Term();

    switch (peek()) {
      // variables
      case '.':
        advance();
        term.type = Term.TermType.VARIABLE;
        term.variable = parseString();
        return term;

      case '[':
        term.type = Term.TermType.BLOCK;
        term.block = parseBlock();
        return term;

      // string literals
      case '\'':
        advance();
        goto default;

      // barewords by default
      default:
        term.type = Term.TermType.STRING;
        term.string_ = parseString();
        return term;
    }
  }

  unittest {
    Term t = (new IxlScanner(".foo")).parseTerm();
    assert(t.type == Term.TermType.VARIABLE);
    assert(t.variable == "foo");

    t = (new IxlScanner(".;")).parseTerm();
    assert(t.type == Term.TermType.VARIABLE);
    assert(t.variable == "");

    t = (new IxlScanner("'{foo}")).parseTerm();
    assert(t.type == Term.TermType.STRING);
    assert(t.string_ == "foo");

    t = (new IxlScanner("[  foo  ]")).parseTerm();
    assert(t.type == Term.TermType.BLOCK);
    assert(t.block.commands.length == 1);
  }

  // whitespace which may include newlines, semicolons, and comments
  void parseWhitespace() {
    consume(" \t\r\n;");

    // consume any comments we find
    while(test('#')) {
      consumeNot("\n");
      consume(" \t\r\n;");
    }
  }

  // inner whitespace
  void parseSpaces() {
    consume(spaces);

    // escaped newlines
    while(test('\\') && test(1, '\n')) {
      advance(2);
      consume(spaces);
    }
  }

  class Flag {
    string name;
    Term argument = null;
  }

  Flag parseFlag() {
    expect('-', "a flag");

    if (test('-')) advance();

    auto flag = new Flag();
    flag.name = parseString();

    parseSpaces();

    if (!test('-') && !test(wordTerminators)) {
      flag.argument = parseTerm();
      parseSpaces();
    }

    return flag;
  }

  // a command.
  // @target cmd opts...
  class Command {
    Term target = null;
    Term call;
    Flag[string] flags;
    Command pipe;
  }

  Command parseCommand() {
    auto command = new Command();

    if (test('@')) {
      advance();
      command.target = parseTerm();
    }

    if (!hasMore()) parseError("expected command");

    command.call = parseTerm();

    parseSpaces();

    while(hasMore()) {
      switch(peek()) {
        case ']':
          return command;

        case ';':
          advance();
          return command;

        // continue pipes after newlines or comments as in
        // a | b | c # comment
        // | d | e
        // | f
        case '\n', '#':
          parseWhitespace();
          if (test('|')) goto case '|';
          else return command;

        case '|':
          advance();
          parseSpaces();
          command.pipe = parseCommand();
          return command;

        case '-':
          auto flag = parseFlag();
          command.flags[flag.name] = flag;
          break;

        default:
          parseError("unflagged command argument");
      }
    }

    return command;
  }

  unittest {
    Command c = (new IxlScanner("foo -f .bar # comment\n other commands")).parseCommand();
    assert(c.target is null);
    assert(c.call !is null);
    assert(c.flags.length == 1);
    assert("f" in c.flags);
    assert(c.flags["f"].argument !is null);
    assert(c.flags["f"].argument.type == Term.TermType.VARIABLE);
    assert(c.flags["f"].argument.variable == "bar");

    c = (new IxlScanner("@.foo -a bar")).parseCommand();
    assert(c.target !is null);
    assert(c.target.type == Term.TermType.VARIABLE);
    assert(c.target.variable == "foo");

    // pipe continuations
    c = (new IxlScanner("foo \n   |bar")).parseCommand();
    assert(c.pipe !is null);
    assert(c.pipe.pipe is null);
  }

  class Program {
    Command[] commands;
  }

  Program parseIxl() {
    auto program = new Program();
    parseWhitespace();

    while (hasMore()) {
      program.commands ~= parseCommand();
      parseWhitespace();
    }

    return program;
  }

  unittest {
    Program p = (new IxlScanner("a | b | c; d | e | f\ng")).parseIxl();
    assert(p.commands.length == 3);
  }
}

IxlScanner.Program parseIxl(in string s) {
  return (new IxlScanner(s)).parseIxl();
}

unittest {
  auto p = parseIxl("  .foo\n");
  assert(p.commands.length == 1);
}
