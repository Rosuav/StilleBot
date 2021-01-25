#if constant(G)
inherit command;
#endif
//TODO-DOCSTRING

int|float binop(int|float left, string op, int|float right) {
	werror("binop: %O %s %O\n", left, op, right);
	switch (op) {
		#define BINARY(o) case #o: return left o right
		BINARY(+); BINARY(-); BINARY(*); BINARY(/); BINARY(%);
		BINARY(<); BINARY(<=); BINARY(==); BINARY(!=); BINARY(>=); BINARY(>);
		BINARY(&&); BINARY(||);
		#undef BINARY
	}
}

string stitch(string l, string r) {return l + r;}
int makeint(string digits) {return (int)digits;}
int|float parens(string open, int|float val, string close) {return val;}

int|float evaluate(string formula) {
	Parser.LR.Parser p = Parser.LR.GrammarParser.make_parser_from_file("modules/calc.grammar");
	int pos;
	//TODO: Handle whitespace in the parser or tokenizer
	formula = replace(formula, ({" ", "\t", "\n"}), "");
	string next() {return pos < sizeof(formula) ? formula[pos..pos++] : "";}
	werror("%O\n", p->parse(next, this));
}

constant legal = "0123456789+-/*() ."; //For now, permit a VERY few characters, for safety.

string process(object channel, object person, string param)
{
	if (param == "") return "@$$: Usage: !calc 1+2";
	if (sizeof((multiset)(array)param - (multiset)(array)legal))
		return "@$$: Illegal character in expression";
	if (mixed ex=catch {
		int|float ret = compile("int|float _() {return "+param+";}")()->_();
		if (intp(ret) || floatp(ret)) return sprintf("@$$: %O", ret);
	}) return "@$$: Invalid expression [" + (describe_error(ex)/"\n")[0] + "]";
	//This shouldn't normally happen - anything that returns a non-int/float will
	//normally trigger a compilation error - but we don't want to be silent.
	return "@$$: Invalid expression [must have real result]";
}

int main(int argc, array(string) argv) {
	string formula = argv[1..] * " ";
	write("Evaluating: %O\n", formula);
	int|float result; 
	if (mixed error = catch {result = evaluate(formula);}) {
		if (stringp(error)) write("Error: %s\n", error); //Evaluator error
		else werror(describe_backtrace(error)); //Pike error
	}
	else write("Result: %O\n", result);
}
