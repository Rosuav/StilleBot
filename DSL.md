Domain-Specific Language
========================

Do I need one? Maybe?

- Come up with a grammar which can compile to the same array/mapping that the command executor runs
- This will confirm that this truly is an AST, and one that can be saved efficiently in JSON
- Go through the validator for features. It's okay if the grammar parses to an inefficient version,
  same as the GUI editor often does. That's what an AST optimization step is for.
- Design goals:
  - Be simple. Avoid unnecessary punctuation.
  - Be unambiguous. Don't omit *necessary* punctuation. This is a DSL not a shell command.
  - Be indentation-safe
    - Maybe have a one-liner version (like semicolon separation, Python style)?
  - Have complexity that scales as linearly as possible
  - Eschew boilerplate of any kind
  - Have all of the power of the command editor
  - Be compact enough to work with in chat
- Hello world should simply be "Hello, world!" - double quotes for a string, and a string is a message.
- Builtins should be entirely generic. Any builtin should be able to become any other.
- Other features (voices etc) may end up being custom syntax, but don't have syntax for everything if
  it's possible to combine some in sensible ways.
- First design a parser, completely external to the main bot. Use Parser.LR same as calc.
- Then design a decompiler that takes the AST and crafts viable source code
- It MAY be worth having a "saved source code" version of a command, which is discarded if you make
  any edit in any other form, but otherwise is retained.
- This might finally be able to replace the Classic editor, which can then be renamed Legacy
