//GTK utility functions/classes lifted straight from Gypsum

//NOTE: In this file, persist is a valid alias for persist_config, for
//compatibility where the code exists also elsewhere (eg Gypsum).
#define persist persist_config

//Usage: gtksignal(some_object,"some_signal",handler,arg,arg,arg) --> save that object.
//Equivalent to some_object->signal_connect("some_signal",handler,arg,arg,arg)
//When this object expires, the signal is disconnected, which should gc the function.
//obj should be a GTK2.G.Object or similar.
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

//A message box that calls its callback only if the user chooses OK. If you need to do cleanup
//on Cancel, use MessageBox above.
class confirm
{
	inherit MessageBox;
	protected void create(int flags,string message,GTK2.Window parent,function cb,mixed|void cb_arg)
	{
		::create(flags,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK_CANCEL,message,parent,cb,cb_arg);
	}
	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback && button==GTK2.RESPONSE_OK) callback(cb_arg);
	}
}

//Advisory note that this widget should be packed without the GTK2.Expand|GTK2.Fill options
//As of Pike 8.0.2, this could safely be done with wid->set_data(), but it's not
//safe to call get_data() with a keyword that hasn't been set (it'll segfault older Pikes).
//So this works with a multiset instead. Once Pike 7.8 support can be dropped, switch to
//get_data to ensure that loose references are never kept.
multiset(GTK2.Widget) _noexpand=(<>);
GTK2.Widget noex(GTK2.Widget wid) {_noexpand[wid]=1; return wid;}

/** Create a GTK2.Table based on a 2D array of widgets
 * The contents will be laid out on the grid. Put a 0 in a cell to span
 * across multiple cells (the object preceding the 0 will span both cells).
 * Use noex(widget) to make a widget not expand (usually will want to do
 * this for a whole column). Shortcut: Labels can be included by simply
 * including a string - it will be turned into a label, expansion off, and
 * with options as set by the second parameter (if any).
 * A leading 0 on a line will be quietly ignored, not resulting in any
 * spanning. Recommended for unlabelled objects in a column of labels.
 */
GTK2.Table GTK2Table(array(array(string|GTK2.Widget)) contents,mapping|void label_opts)
{
	if (!label_opts) label_opts=([]);
	GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),0);
	foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
	{
		int opt=0;
		if (stringp(obj)) {obj=GTK2.Label(label_opts+(["label":obj])); opt=GTK2.Fill;}
		else if (_noexpand[obj]) _noexpand[obj]=0; //Remove it from the set so we don't hang onto references to stuff we don't need
		else opt=GTK2.Fill|GTK2.Expand;
		int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
		tb->attach(obj,x,xend,y,y+1,opt,opt,1,1);
	}
	return tb;
}

//Derivative of GTK2Table above, specific to a two-column layout. Takes a 1D array.
//This is the most normal way to lay out labelled objects - alternate string labels and objects, or use CheckButtons without labels.
//The labels will be right justified.
GTK2.Table two_column(array(string|GTK2.Widget) contents) {return GTK2Table(contents/2,(["xalign":1.0]));}

//End of generic GTK utility classes/functions

//Generic window handler. If a plugin inherits this, it will normally show the window on startup and
//keep it there, though other patterns are possible. For instance, the window might be hidden when
//there's nothing useful to show; although this can cause unnecessary flicker, and so should be kept
//to a minimum (don't show/hide/show/hide in rapid succession). Note that this (via a subclass)
//implements the core window, not just plugin windows, as there's no fundamental difference.
//Transient windows (eg popups etc) are best implemented with nested classes - see usage of configdlg
//('inherit configdlg') for the most common example of this.
class window
{
	constant provides="window";
	mapping(string:mixed) win=([]);
	constant is_subwindow=1; //Set to 0 to disable the taskbar/pager hinting

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
		if (!win->mainwindow) makewindow();
		if (is_subwindow) win->mainwindow->set_transient_for(win->_parentwindow || G->G->window->mainwindow);
		win->mainwindow->set_skip_taskbar_hint(is_subwindow)->set_skip_pager_hint(is_subwindow)->show_all();
		dosignals();
	}
	int closewindow()
	{
		if (win->mainwindow->destroy) win->mainwindow->destroy();
		destruct(win->mainwindow);
		return 1;
	}
}

class configdlg
{
	inherit window;
	//Provide me...
	mapping(string:mixed) windowprops=(["title":"Configure"]);
	mapping(string:mapping(string:mixed)) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping, or something out of persist[] (and see persist_key)
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword.
	constant allow_new=1; //Set to 0 to remove the -- New -- entry; if omitted, -- New -- will be present and entries can be created.
	constant allow_delete=1; //Set to 0 to disable the Delete button (it'll always be visible though)
	constant allow_rename=1; //Set to 0 to ignore changes to keywords
	constant elements=({ });
	constant persist_key=0; //(string) Set this to the persist[] key to load items[] from; if set, persist will be saved after edits.
	constant descr_key=0; //(string) Set this to a key inside the info mapping to populate with descriptions.
	//... end provide me.
	string last_selected; //Set when something is loaded. Unless the user renames the thing, will be equal to win->kwd->get_text().

	protected void create(string|void name)
	{
		if (persist_key && !items) items=persist->setdefault(persist_key,([]));
		::create(!is_subwindow && name); //Unless we're a main window, pass on no args to the window constructor - all configdlgs are independent
	}

	//Return the keyword of the selected item, or 0 if none (or new) is selected
	string selecteditem()
	{
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		return (kwd!="-- New --") && kwd; //TODO: Recognize the "New" entry by something other than its text
	}

	void sig_pb_save_clicked()
	{
		string oldkwd=selecteditem();
		string newkwd=allow_rename?win->kwd->get_text():oldkwd;
		if (newkwd=="") return; //Blank keywords currently disallowed
		if (newkwd=="-- New --") return; //Since selecteditem() currently depends on "-- New --" being the 'New' entry, don't let it be used anywhere else.
		mapping info;
		if (allow_rename) info=m_delete(items,oldkwd); else info=items[oldkwd];
		if (!info)
			if (allow_new) info=([]); else return;
		if (allow_rename) items[newkwd]=info;
		foreach (win->real_strings,string key) info[key]=win[key]->get_text();
		foreach (win->real_ints,string key) info[key]=(int)win[key]->get_text();
		foreach (win->real_bools,string key) info[key]=(int)win[key]->get_active();
		save_content(info);
		if (persist_key) persist->save();
		[object iter,object store]=win->sel->get_selected();
		if (newkwd!=oldkwd)
		{
			if (!oldkwd) win->sel->select_iter(iter=store->insert_before(win->new_iter));
			store->set_value(iter,0,newkwd);
		}
		if (descr_key && info[descr_key]) store->set_value(iter,1,info[descr_key]);
		sig_sel_changed();
	}

	void sig_pb_delete_clicked()
	{
		if (!allow_delete) return; //The button will be insensitive anyway, but check just to be sure.
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		if (!kwd) return;
		store->remove(iter);
		foreach (win->real_strings+win->real_ints,string key) win[key]->set_text("");
		foreach (win->real_bools,string key) win[key]->set_active(0);
		delete_content(kwd,m_delete(items,kwd));
		if (persist_key) persist->save();
	}

	int ischanged()
	{
		string kwd = last_selected; //NOT using selecteditem() here - compare against the last loaded state.
		if (!kwd) return 0; //For now, assume that moving off "-- New --" doesn't need to prompt. TODO.
		if (allow_rename && win->kwd->get_text() != kwd) return 1;
		mapping info = items[kwd] || ([]);
		foreach (win->real_strings, string key)
			if ((info[key] || "") != win[key]->get_text()) return 1;
		foreach (win->real_ints, string key)
			if ((int)info[key] != (int)win[key]->get_text()) return 1;
		foreach (win->real_bools, string key)
			if ((int)info[key] != (int)win[key]->get_active()) return 1;
		return 0;
	}

	void selchange_response(int btn, string kwd)
	{
		string btnname = ([GTK2.RESPONSE_APPLY: "Save", GTK2.RESPONSE_REJECT: "Discard", GTK2.RESPONSE_CANCEL: "Cancel"])[btn] || (string)btn;
		m_delete(win, "save_prompt");
		if (btn == GTK2.RESPONSE_APPLY) sig_pb_save_clicked();
		else if (btn != GTK2.RESPONSE_REJECT) return; //Cancel or closing the window leaves us where we were.
		win->save_prompt = "DISCARD";
		select_keyword(kwd);
		m_delete(win, "save_prompt");
	}

	void sig_sel_changed()
	{
		if (win->save_prompt && win->save_prompt != "DISCARD") return;
		string kwd = selecteditem();
		if (win->save_prompt != "DISCARD" && ischanged())
		{
			win->save_prompt = "PENDING";
			object dlg = MessageBox(0, GTK2.MESSAGE_WARNING, 0, "Unsaved changes will be lost.",
				win->mainwindow, selchange_response, kwd);
			dlg->add_button("_Save", GTK2.RESPONSE_APPLY);
			dlg->add_button("_Discard", GTK2.RESPONSE_REJECT);
			dlg->add_button("_Cancel", GTK2.RESPONSE_CANCEL);
			select_keyword(last_selected);
			return;
		}
		last_selected = kwd;
		mapping info=items[kwd] || ([]);
		if (win->kwd) win->kwd->set_text(kwd || "");
		foreach (win->real_strings,string key) win[key]->set_text((string)(info[key] || ""));
		foreach (win->real_ints,string key) win[key]->set_text((string)info[key]);
		foreach (win->real_bools,string key) win[key]->set_active((int)info[key]);
		load_content(info);
	}

	void makewindow()
	{
		object ls=GTK2.ListStore(({"string","string"}));
		//TODO: Break out the list box code into a separate object - it'd be useful eg for zoneinfo.pike.
		foreach (sort(indices(items)),string kwd)
		{
			object iter=ls->append();
			ls->set_value(iter,0,kwd);
			if (string descr=descr_key && items[kwd][descr_key]) ls->set_value(iter,1,descr);
		}
		if (allow_new) ls->set_value(win->new_iter=ls->append(),0,"-- New --");
		//TODO: Have a way to customize this a little (eg a menu bar) without
		//completely replacing this function.
		win->mainwindow=GTK2.Window(windowprops)
			->add(GTK2.Vbox(0,10)
				->add(GTK2.Hbox(0,5)
					->add(GTK2.ScrolledWindow()->add(
						win->list=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
							->append_column(GTK2.TreeViewColumn("Item",GTK2.CellRendererText(),"text",0))
							->append_column(GTK2.TreeViewColumn("",GTK2.CellRendererText(),"text",1))
					)->set_policy(GTK2.POLICY_NEVER, GTK2.POLICY_AUTOMATIC))
					->add(GTK2.Vbox(0,0)
						->add(make_content())
						->pack_end(GTK2.HbuttonBox()
							->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
							->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1,"sensitive":allow_delete])))
						,0,0,0)
					)
				)
			);
		win->sel=win->list->get_selection(); win->sel->select_iter(win->new_iter||ls->get_iter_first()); sig_sel_changed();
		::makewindow();
	}

	//Generate a widget collection from either the constant or migration mode
	array(string|GTK2.Widget) collect_widgets(array elem)
	{
		array objects = ({ });
		win->real_strings = win->real_ints = win->real_bools = ({ });
		foreach (elem, mixed element)
		{
			sscanf(element, "%1[?#+'@!*]%s", string type, element);
			sscanf(element, "%s:%s", string name, string lbl);
			if (!lbl) sscanf(lower_case(lbl = element)+" ", "%s ", name);
			switch (type)
			{
				case "?": //Boolean
					win->real_bools += ({name});
					objects += ({0,win[name]=noex(GTK2.CheckButton(lbl))});
					break;
				case "#": //Integer
					win->real_ints += ({name});
					objects += ({lbl, win[name]=noex(GTK2.Entry())});
					break;
				case 0: //String
					win->real_strings += ({name});
					objects += ({lbl, win[name]=noex(GTK2.Entry())});
					break;
			}
		}
		win->real_strings -= ({"kwd"});
		return objects;
	}

	//Create and return a widget (most likely a layout widget) representing all the custom content.
	//If allow_rename (see below), this must assign to win->kwd a GTK2.Entry for editing the keyword;
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or
	//it may be a GTK2.Label, or it may be omitted altogether).
	//By default, makes a two_column based on collect_widgets. It's easy to override this to add some
	//additional widgets before or after the ones collect_widgets creates.
	GTK2.Widget make_content()
	{
		return two_column(collect_widgets(elements));
	}

	//Attempt to select the given keyword - returns 1 if found, 0 if not
	int select_keyword(string kwd)
	{
		object ls=win->list->get_model();
		object iter=ls->get_iter_first();
		do
		{
			if (ls->get_value(iter,0)==kwd)
			{
				win->sel->select_iter(iter); sig_sel_changed();
				return 1;
			}
		} while (ls->iter_next(iter));
		return 0;
	}
}
//End code lifted from Gypsum

//All GUI code starts with this file, which also constructs the primary window.
//Normally, the "inherit configdlg" line would be at top level, but in this case,
//the above class definitions have to happen before this one.

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
	mapping config = persist->path("ircsettings");

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Authenticate StilleBot"]))->add(two_column(({
			"Twitch user name", win->nick=GTK2.Entry()->set_text(config->nick||""),
			"Real name (optional)", win->realname=GTK2.Entry()->set_text(config->realname||""),
			"Client ID (optional)", win->clientid=GTK2.Entry()->set_text(config->clientid||""),
			"Client Secret (optional)", win->clientsecret=GTK2.Entry()->set_visibility(0),
			"OAuth2 key", win->pass=GTK2.Entry()->set_visibility(0),
			GTK2.Label("Keys will not be shown above. Obtain"),0,
			GTK2.Label("one from twitchapps and paste it in."),0,
			"Web config address (optional)", win->http_address=GTK2.Entry()->set_text(config->http_address||""),
			"Begin with https:// for an encrypted service - see README", 0,
			"Listen address/port (advanced)", win->listen_address=GTK2.Entry()->set_text(config->listen_address||""),
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
		persist->save();
		closewindow();
		if (!G->G->irc) G->bootstrap_all(); //Force an update to get us connected.
	}
}

object mainwindow;
class _mainwindow
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title": "StilleBot"]);
	constant elements=({"kwd:Channel", "?chatlog:Log chat to console",
		"#connprio:Connection priority",
	});
	constant persist_key = "channels";
	constant is_subwindow = 0;
	protected void create() {::create("mainwindow"); remake_content(); mainwindow = win->mainwindow;}

	void makewindow()
	{
		::makewindow();
		//Add a menu bar. This is a bit of a hack.
		object vbox = win->mainwindow->get_child();
		object menubar = GTK2.MenuBar()
			->add(GTK2.MenuItem("_Options")->set_submenu(win->optmenu=GTK2.Menu()
				->add(win->update=GTK2.MenuItem("Update (developer mode)"))
				->add(win->updatemodules=GTK2.MenuItem("Update modules (developer mode)"))
				->add(win->manual_auth=GTK2.MenuItem("Authenticate manually"))
			));
		vbox->pack_start(menubar,0,0,0)->reorder_child(menubar, 0);
	}

	void sig_kwd_changed(object self)
	{
		string txt = self->get_text();
		string lc = lower_case(txt);
		if (lc != txt) self->set_text(lc);
	}

	GTK2.Widget make_content() {return win->contentblock = ::make_content();}
	void remake_content()
	{
		object parent = win->contentblock->get_parent();
		parent->remove(win->contentblock);
		parent->add(make_content()->show_all());
		dosignals(); //For some reason, updating code redoes signals BEFORE triggering this.
		sig_sel_changed();
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

	void save_content(mapping(string:mixed) info)
	{
		string kwd = win->kwd->get_text();
		if (!G->G->irc->channels["#" + kwd]) function_object(send_message)->reconnect();
	}
	void delete_content(string kwd,mapping(string:mixed) info) {function_object(send_message)->reconnect();}

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
