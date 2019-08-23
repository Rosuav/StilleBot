mapping irc = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([]);
mapping headers = (["Authorization": replace(irc["pass"], "oauth:", "OAuth "), "Client-ID": irc["clientid"]]);
string channel = "rosuav";

//Code lifted from Pike's Protocols.HTTP.Promise (GPLv2) for testing
protected class Session
{
  inherit Protocols.HTTP.Session : parent;
  class Request
  {
    inherit parent::Request;
    protected void async_ok(object q)
    {
      con->set_callbacks(0, 0);
      con->timed_async_fetch(async_data, async_fail); // start data downloading
    }

    protected void async_data() {
      string s = con->data();
      con->set_callbacks(0, 0);
      function dc = data_callback;
      set_callbacks(0, 0, 0); // drop all references
      dc(s);
    }
  }
}
//End GPLv2 code from Pike

Session gsess = Session();
void poll()
{
	call_out(poll, 1);
	write("Polling... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	Session lsess = Session();
	//Change lsess to gsess here to remove the leak
	lsess->async_do_method_url("GET", "https://api.twitch.tv/helix/streams?user_login=" + channel, 0, 0, headers, 0,
		lambda(string res) {
			mixed raw = Standards.JSON.decode_utf8(res);
			if (!sizeof(raw->data)) write("** Channel %s is offline **\n", channel);
			else write("** Channel %s went online at %s **\n", channel, raw->data[0]->started_at);
		}, 0, ({ }));
}

int main() {write("My PID is: %d\n", getpid()); poll(); return -1;}
