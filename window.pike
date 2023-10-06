class gtksignal(object obj)
{
	int signal_id;
	protected void create(mixed ... args) {if (obj) signal_id=obj->signal_connect(@args);}
	protected void destroy() {if (obj && signal_id) obj->signal_disconnect(signal_id);}
	protected void _destruct() {if (obj && signal_id) obj->signal_disconnect(signal_id);}
}

class MessageBox
{
	inherit GTK2.MessageDialog;
	function callback;

	//flags: Normally 0. type: 0 for info, else GTK2.MESSAGE_ERROR or similar. buttons: GTK2.BUTTONS_OK etc.
	protected void create(int flags,int type,int buttons,string message,GTK2.Window parent,function|void cb,mixed|void cb_arg)
	{
		callback=cb;
		::create(flags,type,buttons,message,parent);
		signal_connect("response",response,cb_arg);
		show();
	}

	void response(object self,int button,mixed cb_arg)
	{
		if (self->destroy) self->destroy();
		if (callback) callback(button,cb_arg);
		destruct();
	}
}

GTK2.Table two_column(array(array|string|GTK2.Widget) contents) {
	contents /= 2;
	GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),0);
	foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
	{
		int opt=0;
		if (stringp(obj)) {obj=GTK2.Label((["xalign": 1.0, "label":obj])); opt=GTK2.Fill;}
		int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
		tb->attach(obj,x,xend,y,y+1,opt,opt,1,1);
	}
	return tb;
}

class window
{
	constant provides="window";
	constant windowtitle = "Window";
	mapping(string:mixed) win=([]);

	//Replace this and call the original after assigning to win->mainwindow.
	void makewindow() {if (win->accelgroup) win->mainwindow->add_accel_group(win->accelgroup);}

	//Stock item creation: Close button. Calls closewindow(), same as clicking the cross does.
	GTK2.Button stock_close()
	{
		return win->stock_close=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_CLOSE]));
	}

	//Subclasses should call ::dosignals() and then append to to win->signals. This is the
	//only place where win->signals is reset. Note that it's perfectly legitimate to have
	//nulls in the array, as exploited here.
	void dosignals()
	{
		//NOTE: This does *not* use += here - this is where we (re)initialize the array.
		win->signals = ({
			gtksignal(win->mainwindow,"delete_event",closewindow),
			win->stock_close && gtksignal(win->stock_close,"clicked",closewindow),
		});
		collect_signals("sig_", win);
	}

	//NOTE: prefix *must* be a single 'word' followed by an underscore. Stuff breaks otherwise.
	void collect_signals(string prefix, mapping(string:mixed) searchme,mixed|void arg)
	{
		foreach (indices(this),string key) if (has_prefix(key,prefix) && callablep(this[key]))
		{
			//Function names of format sig_x_y become a signal handler for win->x signal y.
			//(Note that classes are callable, so they can be used as signal handlers too.)
			//This may pose problems, as it's possible for x and y to have underscores in
			//them, so we scan along and find the shortest such name that exists in win[].
			//If there's none, ignore the callable (currently without any error or warning,
			//despite the explicit prefix). This can create ambiguities, but only in really
			//contrived situations, so I'm deciding not to care. :)
			array parts=(key/"_")[1..];
			int b4=(parts[0]=="b4"); if (b4) parts=parts[1..]; //sig_b4_some_object_some_signal will connect _before_ the normal action
			for (int i=0;i<sizeof(parts)-1;++i) if (mixed obj=searchme[parts[..i]*"_"])
			{
				if (objectp(obj) && callablep(obj->signal_connect))
				{
					win->signals+=({gtksignal(obj,parts[i+1..]*"_",this[key],arg,UNDEFINED,b4)});
					break;
				}
			}
		}
	}
	protected void create(string|void name)
	{
		if (name) sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) {if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;}
		win->self=this;
		if (!win->mainwindow) win->mainwindow = GTK2.Window((["title": windowtitle]));
		else win->mainwindow->remove(win->mainwindow->get_child());
		makewindow();
		win->mainwindow->show_all();
		dosignals();
	}
	int closewindow()
	{
		if (win->mainwindow->destroy) win->mainwindow->destroy();
		destruct(win->mainwindow);
		return 1;
	}
}

class menu_item
{
	//Provide:
	constant menu_label=0; //(string) The initial label for your menu item.
	void menu_clicked() { }
	//End provide.

	GTK2.MenuItem make_menu_item() {return GTK2.MenuItem(menu_label);} //Override if customization is required
	protected void create(string|void name)
	{
		if (!name) return;
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (object old=G->G->menuitems[name]) {({old->destroy})(); destruct(old);}
		object mi = make_menu_item();
		G->G->windows->mainwindow->optmenu->add(mi->show());
		mi->signal_connect("activate",menu_clicked);
		G->G->menuitems[name] = mi;
	}
}

class ircsettings
{
	inherit window;
	constant windowtitle = "Authenticate StilleBot";
	mapping config = persist_config->path("ircsettings");

	void makewindow()
	{
		win->mainwindow->add(two_column(({
			"Twitch user name", win->nick=GTK2.Entry()->set_size_request(400, -1)->set_text(config->nick||""),
			"Real name (optional)", win->realname=GTK2.Entry()->set_size_request(400, -1)->set_text(config->realname||""),
			"Client ID (optional)", win->clientid=GTK2.Entry()->set_size_request(400, -1)->set_text(config->clientid||""),
			"Client Secret (optional)", win->clientsecret=GTK2.Entry()->set_size_request(400, -1)->set_visibility(0),
			"OAuth2 key", win->pass=GTK2.Entry()->set_size_request(400, -1)->set_visibility(0),
			GTK2.Label("Keys will not be shown above. Obtain"),0,
			GTK2.Label("one from twitchapps and paste it in."),0,
			"Web config address (optional)", win->http_address=GTK2.Entry()->set_size_request(400, -1)->set_text(config->http_address||""),
			"Begin with https:// for an encrypted service - see README", 0,
			"Listen address/port (advanced)", win->listen_address=GTK2.Entry()->set_size_request(400, -1)->set_text(config->listen_address||""),
			GTK2.HbuttonBox()
				->add(win->save=GTK2.Button("Save"))
				->add(stock_close())
			,0
		})));
	}

	void sig_save_clicked()
	{
		config->nick = win->nick->get_text();
		config->realname = win->realname->get_text();
		config->clientid = win->clientid->get_text();
		string secret = win->clientsecret->get_text();
		if (secret != "") config->clientsecret = secret;
		string pass = win->pass->get_text();
		if (has_prefix(pass, "oauth:")) config->pass = pass;
		config->http_address = win->http_address->get_text();
		if (!sscanf(config->http_address, "http%*[s]://%s", string addr) || !addr)
			config->http_address = "http://" + config->http_address;
		if (has_suffix(config->http_address, "/")) config->http_address = config->http_address[..<1]; //Strip trailing slash
		config->listen_address = win->listen_address->get_text();
		persist_config->save();
		closewindow();
		if (!G->G->irc) G->bootstrap_all(); //Force an update to get us connected.
	}
}

object mainwindow;
class _mainwindow
{
	inherit window;
	constant windowtitle = "StilleBot";

	protected void create() {
		::create("mainwindow");
		mainwindow = win->mainwindow;
	}

	//Return the keyword of the selected item, or 0 if none (or new) is selected
	string selecteditem()
	{
		[object iter,object store]=win->sel->get_selected();
		string login = iter && store->get_value(iter, 0);
		return (login != "-- New --") && login; //TODO: Recognize the "New" entry by something other than its text
	}

	void sig_pb_save_clicked()
	{
		string login = selecteditem();
		if (!login) { //Connect to new channel
			login = win->login->get_text();
			if (login == "" || login == "-- New --") return; //Invalid names
			spawn_task(connect_to_channel(login)) {[mapping info] = __ARGS__;
				sig_pb_refresh_clicked();
				object iter = win->ls->get_iter_first();
				while (win->ls->get_value(iter, 0) != login)
					if (!win->ls->iter_next(iter)) {iter = win->new_iter; break;}
				win->sel->select_iter(iter);
				//win->list->scroll_to_cell(iter->get_path(), 0); //Doesn't seem to work. Whatever.
				info->connprio = (int)win->connprio->get_text();
				info->chatlog = (int)win->chatlog->get_active();
				persist_config->save();
			};
			return;
		}
		mapping info = get_channel_config(login); if (!info) return; //TODO: Report error?
		info->connprio = (int)win->connprio->get_text();
		info->chatlog = (int)win->chatlog->get_active();
		persist_config->save();
		sig_sel_changed();
	}

	void sig_pb_delete_clicked()
	{
		[object iter,object store]=win->sel->get_selected();
		string login = iter && store->get_value(iter, 0);
		if (!login || login == "-- New --") return;
		store->remove(iter);
		m_delete(persist_config["channels"], login); //FIXME-SEPCHAN
		persist_config->save();
		function_object(send_message)->reconnect();
	}

	void sig_sel_changed()
	{
		string login = selecteditem();
		mapping cfg = get_channel_config(login) || ([]);
		win->login->set_text(login || "");
		win->display_name->set_text(cfg->display_name || "");
		win->connprio->set_text((string)cfg->connprio);
		win->chatlog->set_active((int)cfg->chatlog);
	}

	void makewindow()
	{
		win->mainwindow->add(GTK2.Vbox(0,10)
				->pack_start(GTK2.MenuBar()
					->add(GTK2.MenuItem("_Options")->set_submenu(win->optmenu=GTK2.Menu()
						->add(win->update=GTK2.MenuItem("Update (developer mode)"))
						->add(win->updatemodules=GTK2.MenuItem("Update modules (developer mode)"))
						->add(win->manual_auth=GTK2.MenuItem("Authenticate manually"))
					)),0,0,0)
				->add(GTK2.Hbox(0,5)
					->add(GTK2.ScrolledWindow()->add(
						win->list = GTK2.TreeView(win->ls = GTK2.ListStore(({"string", "string"})))
							->append_column(GTK2.TreeViewColumn("Login", GTK2.CellRendererText(), "text", 0))
							->append_column(GTK2.TreeViewColumn("ID", GTK2.CellRendererText(), "text", 1))
					)->set_policy(GTK2.POLICY_NEVER, GTK2.POLICY_AUTOMATIC))
					->add(GTK2.Vbox(0,0)
						->add(two_column(({
							"Channel", win->login = GTK2.Entry(),
							"Displays as", win->display_name = GTK2.Label(),
							0, win->chatlog = GTK2.CheckButton("Log chat to console"),
							"Connection priority", win->connprio = GTK2.Entry(),
						})))
						->pack_end(GTK2.HbuttonBox()
							->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
							->add(win->pb_refresh=GTK2.Button((["label":"_Refresh","use-underline":1])))
							->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1,"sensitive":1])))
						,0,0,0)
					)
				)
			);
		win->sel=win->list->get_selection();
		sig_pb_refresh_clicked();
		sig_sel_changed();
		::makewindow();
	}

	void sig_pb_refresh_clicked() {
		win->ls->clear();
		array configs = list_channel_configs(); sort(configs->login, configs);
		foreach (configs, mapping cfg) {
			object iter = win->ls->append();
			win->ls->set_value(iter, 0, cfg->login || "...");
			win->ls->set_value(iter, 1, (string)cfg->userid);
		}
		win->ls->set_value(win->new_iter = win->ls->append(), 0, "-- New --");
		win->sel->select_iter(win->new_iter);
	}

	void sig_login_changed(object self)
	{
		string txt = self->get_text();
		string lc = lower_case(txt);
		if (lc != txt) self->set_text(lc);
	}

	void sig_update_activate(object self)
	{
		//object main = G->bootstrap("stillebot.pike"); //Test new bootstrap code
		//int err = main ? main->bootstrap_all() : 1;
		int err = G->bootstrap_all(); //Normally the current bootstrap code is fine.
		gc();
		if (!err) return; //All OK? Be silent.
		if (string winid = getenv("WINDOWID")) //On some Linux systems we can pop the console up.
			catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait()); //Try, but don't mind errors, eg if wmctrl isn't installed.
		MessageBox(0, GTK2.MESSAGE_ERROR, GTK2.BUTTONS_OK, err + " compilation error(s) - see console", win->mainwindow);
	}
	void sig_updatemodules_activate(object self)
	{
		int err = 0;
		foreach (sort(get_dir("modules")), string f)
			if (has_suffix(f, ".pike")) err += !G->bootstrap("modules/" + f);
		foreach (sort(get_dir("modules/http")), string f)
			if (has_suffix(f, ".pike")) err += !G->bootstrap("modules/http/" + f);
		foreach (sort(get_dir("zz_local")), string f)
			if (has_suffix(f, ".pike")) err += !G->bootstrap("zz_local/" + f);
		gc();
		if (!err) return; //All OK? Be silent.
		if (string winid = getenv("WINDOWID")) //On some Linux systems we can pop the console up.
			catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait()); //Try, but don't mind errors, eg if wmctrl isn't installed.
		MessageBox(0, GTK2.MESSAGE_ERROR, GTK2.BUTTONS_OK, err + " compilation error(s) - see console", win->mainwindow);
	}

	void sig_manual_auth_activate() {ircsettings();}

	void closewindow() {exit(0);}
}

protected void create(string name)
{
	add_constant("window", window);
	add_constant("menu_item", menu_item);
	if (!G->G->windows)
	{
		//First time initialization
		G->G->windows = ([]);
		G->G->argv = GTK2.setup_gtk(G->G->argv);
	}
	G->G->window = this;
	if (G->G->menuitems)
	{
		array mi = values(G->G->menuitems);
		mi->destroy();
		destruct(mi[*]);
	}
	G->G->menuitems = ([]);
	_mainwindow();
}
