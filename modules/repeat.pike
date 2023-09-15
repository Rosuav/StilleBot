inherit command;
inherit hook; //Ensure that residual hooks get purged
constant active_channels = ({""}); //Replaced with the cmdmgr builtin

void autospam(string channel, string msg) { }
echoable_message process(object channel, mapping person, string param) {return "DISABLED";}

protected void create(string name)
{
	::create(name);
	register_bouncer(autospam);
	G->G->commands["unrepeat"] = process;
}
