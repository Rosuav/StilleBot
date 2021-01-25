inherit command;
constant docstring = #"
Calculate something, possibly involving channel variables

Usage: `!calc 1 + 2 * 3`

If you are a moderator, this will expand variables. This is therefore
the quickest way to see the value of any variable:

`!calc $deaths$`

To avoid leaking private variables to non-moderators, unfortunately
this feature must be restricted. But numbers themselves are fine :)
";

int|float binop(int|float left, string op, int|float right) {
	switch (op) {
		#define BINARY(o) case #o: return left o right
		BINARY(+); BINARY(-); BINARY(*); BINARY(/); BINARY(%);
		BINARY(<); BINARY(<=); BINARY(==); BINARY(!=); BINARY(>=); BINARY(>);
		BINARY(&&); BINARY(||); BINARY(**);
		#undef BINARY
		//Some aliases for the convenience of humans
		//We won't have assignment here (or if we do, bring on the
		//walrus operator), nor bitwise operations, so it's nicer
		//to let people use these in other natural ways.
		case "=": return left == right;
		case "&": return left && right;
		case "|": return left || right;
		case "=>": return left >= right;
	}
}

string stitch(string ... parts) {return parts * "";}
int makeint(string digits) {return (int)digits;}
float makefloat(string digits) {return (float)digits;}
int|float parens(string open, int|float val, string close) {return val;}

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("modules/calc.grammar");
void throw_errors(int level, string subsystem, string msg, mixed ... args) {if (level >= 2) error(msg, @args);}

int|float evaluate(string formula) {
	parser->set_error_handler(throw_errors);
	string next() {
		if (formula == "") return "";
		sscanf(formula, "%*[ \t\n]%s", formula); //TODO: Handle whitespace in the grammar properly
		sscanf(formula, "%[*&|<=>!]%s", string token, formula); //All characters that can be part of multi-character tokens
		if (token == "") sscanf(formula, "%1s%s", token, formula); //Otherwise, grab a single character
		return token;
	}
	return parser->parse(next, this);
}

string process(object channel, object person, string param)
{
	if (param == "") return "@$$: Usage: !calc 1+2";
	if (person->badges->_mod) param = channel->expand_variables(param);
	mixed ex = catch {return sprintf("@$$: %O", evaluate(param));};
	return "@$$: Invalid expression [" + (describe_error(ex)/"\n")[0] + "]";
}

void create(string name) {::create(name); G->G->evaluate_expr = evaluate;}
