/* Chat bot for Twitch.tv
See API docs:
https://github.com/justintv/Twitch-API/blob/master/IRC.md

To make this work, get yourself an oauth key here:
http://twitchapps.com/tmi/
and change your user and realname accordingly.
*/

array(string) bootstrap_files = ({"globals.pike", "poll.pike", "connection.pike", "window.pike"});
mapping G = ([]);
function(string:void) execcommand;

void console(object stdin, string buf)
{
	while (has_value(buf, "\n"))
	{
		sscanf(buf, "%s\n%s", string line, buf);
		execcommand(line);
	}
	if (buf!="") execcommand(buf);
}

object bootstrap(string c)
{
	program|object compiled;
	mixed ex=catch {compiled=compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return 0;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex=catch {compiled = compiled(c);}) werror(describe_backtrace(ex)+"\n");
	werror("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	object main = bootstrap(__FILE__);
	if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return 1;}
	int err = 0;
	foreach (bootstrap_files = main->bootstrap_files, string fn)
		if (file_stat(fn)->isdir) foreach (sort(get_dir(fn)), string f) err += !bootstrap(fn+"/"+f);
		else err += !bootstrap(fn);
	return err;
}

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	G->argv = argv;
	bootstrap_all();
	Stdio.stdin->set_read_callback(console);
	return -1;
}
