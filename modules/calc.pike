#if constant(G)
inherit command;
#endif
//TODO-DOCSTRING

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

int|float evaluate(string formula) {
	Parser.LR.Parser p = Parser.LR.GrammarParser.make_parser_from_file("modules/calc.grammar");
	string next() {
		if (formula == "") return "";
		sscanf(formula, "%*[ \t\n]%s", formula); //TODO: Handle whitespace in the grammar properly
		sscanf(formula, "%[*&|<=>!]%s", string token, formula); //All characters that can be part of multi-character tokens
		if (token == "") sscanf(formula, "%1s%s", token, formula); //Otherwise, grab a single character
		return token;
	}
	return p->parse(next, this);
}

string process(object channel, object person, string param)
{
	if (param == "") return "@$$: Usage: !calc 1+2";
	param = channel->expand_variables(param);
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
