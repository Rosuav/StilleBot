#if constant(G)
inherit command;
#endif
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
	}
}

string stitch(string ... parts) {return parts * "";}
int makeint(string digits) {return (int)digits;}
float makefloat(string digits) {return (float)digits;}
int|float parens(string open, int|float val, string close) {return val;}

Parser.LR.Parser parser = Parser.LR.GrammarParser.make_parser_from_file("modules/calc.grammar");
void throw_errors(mixed level, string subsystem, string msg, mixed ... args) {error(msg, @args);}
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

//Stand-alone testing
int main(int argc, array(string) argv) {
	string formula = argv[1..] * " ";
	write("Evaluating: %O\n", formula);
	if (mixed error = catch {write("Result: %O\n", evaluate(formula));})
		werror(describe_backtrace(error));
}
