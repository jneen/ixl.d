import std.stdio;
import std.ascii;
import std.string;

extern(C) int isatty(int);

class Node {
  string tag;

  string payload;
  Node[] children;

  this(string t, string p) { tag = t; payload = p; }
  this(string t) { tag = t; children = []; }

  string inspect() {
    if (payload) {
      return format("(%s (%s))", tag, payload);
    }
    else {
      string[] childForms;

      foreach(child; this.children) childForms ~= child.inspect();

      return format("(%s (%s))", tag, childForms.join(" "));
    }
  }

  unittest {
    Node n = new Node("a-tag");
    n.children ~= new Node("foo", "bar");
    n.children ~= new Node("baz", "zot");
    assert(n.inspect() == "(a-tag ((foo (bar)) (baz (zot))))");
  }
}

class Scanner {
  string s;
  size_t pos = 0;

  this(in string s) { this.s = s; }

  char peek() { return peek(0); }

  char peek(size_t n) {
    return s[n + pos];
  }

  bool test(char ch) {
    return hasMore() && peek() == ch;
  }

  bool test(string st) {
    if (!hasMore(st.length)) return false;

    for (size_t i = 0; i < st.length; ++i) {
      if (peek(i) != st[i]) return false;
    }

    return true;
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

int main(string[] argv) {
  if (argv.length > 1 && argv[1] == "--test") return 0;

  string input;
  readf("%s", &input);

  writeln(parseIxl(input).inspect());
  return 0;
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

  Node parseBlock() {
    auto block = new Node("block");
    expect('[', "a block");

    parseWhitespace();
    while(hasMore()) {
      if (peek() == ']') return block;

      block.children ~= parseCommand();
    }

    parseError("unexpected EOF");

    // won't get here :(
    return block;
  }

  unittest {
    auto n = (new IxlScanner("[]")).parseBlock();
    assert(n.tag == "block");
    assert(n.children.length == 0);

    n = (new IxlScanner("[foo --bar]")).parseBlock();
    assert(n.tag == "block");
    assert(n.children.length == 1);
    assert(n.children[0].tag == "command");
    assert(n.children[0].children.length == 2);
    assert(n.children[0].children[0].tag == "string");
    assert(n.children[0].children[0].payload == "foo");
    assert(n.children[0].children[1].tag == "flag");
    writeln(n.inspect());
    assert(n.children[0].children[1].children.length == 1);
    assert(n.children[0].children[1].children[0].payload == "bar");

    n = (new IxlScanner("[[]]")).parseBlock();
  }

  Node parseTerm() {
    switch (peek()) {
      // variables
      case '.':
        advance();
        return new Node("variable", parseString());

      // string literals
      case '\'':
        advance();
        return new Node("string", parseString());

      case '[':
        return parseBlock();

      // barewords by default
      default:
        return new Node("string", parseString());
    }
  }

  unittest {
    auto n = (new IxlScanner(".foo")).parseTerm();
    assert(n.tag == "variable");
    assert(n.payload == "foo");
  }

  // whitespace which may include newlines and semicolons
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
    while(test("\\\n")) {
      advance(2);
      consume(spaces);
    }
  }

  Node parseFlag() {
    expect('-', "a flag");

    if (test('-')) advance();

    auto flag = new Node("flag");
    flag.children ~= new Node("string", parseString());

    parseSpaces();

    if (!test('-')) {
      flag.children ~= parseTerm();
      parseSpaces();
    }

    return flag;
  }

  // a command.
  // @target cmd opts...
  Node parseCommand() {
    auto command = new Node("command");

    if (test('@')) {
      advance();
      auto target = new Node("target");
      target.children ~= parseTerm();
      command.children ~= target;
    }

    writeln(inspect());
    if (hasMore()) {
      command.children ~= parseTerm();
      parseSpaces();
    }

    writeln(inspect());

    while(hasMore()) {
      writeln(inspect());
      switch(peek()) {
        case ']', ';':
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
          auto pipe = new Node("pipe");
          advance(); parseWhitespace();
          command.children ~= pipe;
          pipe.children ~= parseCommand();
          return command;

        case '-':
          command.children ~= parseFlag();
          break;

        default:
          parseError("unflagged command argument");
      }
    }

    return command;
  }

  unittest {
    auto n = (new IxlScanner("foo -f .bar # comment\n other commands")).parseCommand();
    assert(n.tag == "command");
    assert(n.children.length == 2);
    assert(n.children[0].tag == "string");
    assert(n.children[0].payload == "foo");
    assert(n.children[1].tag == "variable");
    assert(n.children[1].payload == "bar");

    n = (new IxlScanner("@.{foo} -a bar")).parseCommand();
    assert(n.tag == "command");
    assert(n.children.length > 0);
    assert(n.children[0].tag == "target");
    assert(n.children[0].children.length == 1);
    assert(n.children[0].children[0].tag == "variable");
    assert(n.children[0].children[0].payload == "foo");

    // pipe continuations
    n = (new IxlScanner("foo \n   |bar")).parseCommand();
    assert(n.children.length == 2);
    assert(n.children[1].tag == "pipe");
  }

  Node parseIxl() {
    auto program = new Node("program");
    parseWhitespace();

    while (hasMore()) {
      program.children ~= parseCommand();
      parseWhitespace();
    }

    return program;
  }

  unittest {
    auto p = (new IxlScanner("a | b | c; d | e | f\ng")).parseIxl();
    assert(p.tag == "program");
    assert(p.children.length == 3);
  }
}

Node parseIxl(in string s) {
  return (new IxlScanner(s)).parseIxl();
}

unittest {
  auto node = parseIxl("  .foo\n");
  assert(node.tag == "program");

  assert(node.children.length == 1);
  assert(node.children[0].tag == "command");
}
