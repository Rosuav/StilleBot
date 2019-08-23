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
    protected void async_fail(object q)
    {
      con->set_callbacks(0, 0);
      set_callbacks(0, 0, 0); // drop all references
    }

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

    //If this function is removed, Session::_destruct isn't called either.
    //If it's present, even with no code in it, Session::_destruct IS called.
    protected void _destruct() {				
      werror("%O()._destruct()\n", object_program(this)); 
    }
  }


  protected void _destruct() {				
    werror("%O()._destruct()\n", object_program(this)); 
  }
}

void get_url(Protocols.HTTP.Session.URL url, mapping headers, function cb)
{
  Session s = Session(); //If this is retained, the leak vanishes
  s->async_do_method_url("GET", url, 0, 0, headers, 0, cb, 0, ({ }));
}
//End GPLv2 code from Pike

void poll()
{
	call_out(poll, 3);
	write("Polling... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	get_url("https://api.twitch.tv/helix/streams?user_login=" + channel, headers, lambda(string res) {
		mixed raw = Standards.JSON.decode_utf8(res);
		if (!sizeof(raw->data)) write("** Channel %s is offline **\n", channel);
		else write("** Channel %s went online at %s **\n", channel, raw->data[0]->started_at);
	});
}

int main() {write("My PID is: %d\n", getpid()); poll(); return -1;}
