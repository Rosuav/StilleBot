//Stand-alone listener - a massively cut-down version of connection.pike
//Requires the oauth password to be in a file called 'pwd'.

void not_message(object person,string msg)
{
	if (sscanf(msg, "\1ACTION %s\1", string slashme)) write("%s %s\n", person->nick, slashme);
	else write("%s: %s\n", person->nick, msg);
}
//Stubs because older Pikes don't include all of these by default
void not_join(object who) {write("[join %s]\n", who->nick);}
void not_part(object who, string message, object executor) {write("[part %s]\n", who->nick);}
void not_mode(object who, string mode) {write("[mode %s %s]\n", who->nick, mode);}
void not_failed_to_join() { }
void not_invite(object who) { }

object irc;
void console(object stdin, string buf)
{
	while (has_value(buf, "\n"))
	{
		sscanf(buf, "%s\n%s", string line, buf);
		irc->send_message("#rosuav", string_to_utf8(line));
	}
	if (buf!="") irc->send_message("#rosuav", string_to_utf8(buf));
}

int main(int argc, array(string) argv)
{
	mapping opts = (["nick": "Rosuav", "realname": "Chris Angelico", "pass": String.trim_all_whites(Stdio.read_file("pwd"))]);
	irc = Protocols.IRC.Client("irc.chat.twitch.tv", opts);
	irc->cmd->join("#rosuav");
	irc->channels["#rosuav"] = this;
	if (argc > 1 && argv[1] == "console")
	{
		Stdio.stdin->set_read_callback(console);
		write("Console active.\n");
	}
	return -1;
}
