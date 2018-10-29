inherit command;
constant require_allcmds = 1;
inherit menu_item;
constant menu_label = "Recent raids";
constant active_channels = ({"!whisper"});

mapping(string:array(string)) get_raids()
{
	
}

void menu_clicked()
{
	write("-- recent raid lookup --\n");
	if (string winid = getenv("WINDOWID")) //Copied from window.pike
		catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait());
}

string process(object channel, object person, string param)
{
	return "-- recent raid lookup by whisper --";
}

void create(string name) {::create(name);}
