inherit command;
//TODO-DOCSTRING

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
