import std.stdio;
import std.ascii;
import std.string;

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

  string advance(size_t n) {
    assert(pos <= s.length - n);

    pos += n;
    return s[ pos - n .. pos ];
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

    payload = s.advance(1);
    assert(s.pre() == "  foo\n");
    assert(s.post() == "bar");
    assert(payload == "\n");
  }
}

int main() {
  return 0;
}

class IxlScanner : Scanner {
  enum spaces = " \t";

  this(in string s) { super(s); }

  // parses a bareword or a {}-delimited balanced string.
  string parseString() {
    if (!hasMore() || peek() != '{') return consumeNot(whitespace);

    int braceCount = 0;
    size_t marker = this.pos + 1;

    while (hasMore()) {
      switch(peek()) {
        case '{':
          advance(1);
          ++braceCount;
          break;

        case '}':
          advance(1);
          --braceCount;
          if (braceCount == 0) goto end;
          break;

        case '\\':
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

  Node parseTerm() {
    switch (peek()) {
      case '.':
        advance(1);
        return new Node("variable", parseString());
      case '\'':
        advance(1);
        return new Node("string", parseString());
      default:
        return new Node("string", parseString());
    }
  }

  void parseWhitespace() {
    consume(whitespace);

    // consume any comments we find
    while(hasMore() && peek() == '#') {
      consumeNot("\n");
      consume(whitespace);
    }
  }

  void parseSpaces() {
    consume(spaces);

    // escaped newlines
    while(hasMore() && peek(0) == '\\' && peek(1) == '\n') {
      advance(2);
      consume(spaces);
    }
  }

  Node parseCommand() {
    auto command = new Node("command");

    while(hasMore()) {
      switch(peek()) {
        case '\n', '#':
          return command;

        case '|':
          auto pipe = new Node("pipe");
          advance(1); parseWhitespace();
          command.children ~= pipe;
          pipe.children ~= parseCommand();
          return command;

        default:
          command.children ~= parseTerm();
      }
      parseSpaces();
    }

    return command;
  }

  Node parseIxl() {
    auto program = new Node("program", "");
    parseWhitespace();

    while (hasMore()) {
      switch(peek()) {
        case '#': consumeNot("\n"); break;
        default:
          program.children ~= parseCommand();
      }
      parseWhitespace();
    }

    return program;
  }

  unittest {
    auto n = (new IxlScanner(".foo")).parseTerm();
    assert(n.tag == "variable");
    assert(n.payload == "foo");

    n = (new IxlScanner("foo .bar # comment\n other commands")).parseCommand();
    assert(n.tag == "command");
    assert(n.children.length == 2);
    assert(n.children[0].tag == "string");
    assert(n.children[0].payload == "foo");
    assert(n.children[1].tag == "variable");
    assert(n.children[1].payload == "bar");

    string parsed = (new IxlScanner("{asdf}")).parseString();
    assert(parsed == "asdf");

    parsed = (new IxlScanner("{a{{s{}d{f}}}}")).parseString();
    assert(parsed == "a{{s{}d{f}}}");
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
