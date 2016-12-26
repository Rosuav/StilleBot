//GTK utility functions/classes lifted straight from Gypsum


//Usage: gtksignal(some_object,"some_signal",handler,arg,arg,arg) --> save that object.
//Equivalent to some_object->signal_connect("some_signal",handler,arg,arg,arg)
//When this object expires, the signal is disconnected, which should gc the function.
//obj should be a GTK2.G.Object or similar.
class gtksignal(object obj)
{
	int signal_id;
	void create(mixed ... args) {if (obj) signal_id=obj->signal_connect(@args);}
	void destroy() {if (obj && signal_id) obj->signal_disconnect(signal_id);}
}

class MessageBox
{
	inherit GTK2.MessageDialog;
	function callback;

	//flags: Normally 0. type: 0 for info, else GTK2.MESSAGE_ERROR or similar. buttons: GTK2.BUTTONS_OK etc.
	void create(int flags,int type,int buttons,string message,GTK2.Window parent,function|void cb,mixed|void cb_arg)
	{
		callback=cb;
		#if constant(COMPAT_MSGDLG)
		//There's some sort of issue in older Pikes (7.8 only) regarding the parent.
		//TODO: Hunt down what it was and put a better note here.
		::create(flags,type,buttons,message);
		#else
		::create(flags,type,buttons,message,parent);
		#endif
		signal_connect("response",response,cb_arg);
		show();
	}

	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback) callback(button,cb_arg);
	}
}

//A message box that calls its callback only if the user chooses OK. If you need to do cleanup
//on Cancel, use MessageBox above.
class confirm
{
	inherit MessageBox;
	void create(int flags,string message,GTK2.Window parent,function cb,mixed|void cb_arg)
	{
		::create(flags,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK_CANCEL,message,parent,cb,cb_arg);
	}
	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback && button==GTK2.RESPONSE_OK) callback(cb_arg);
	}
}

//Exactly the same as a GTK2.TextView but with additional methods for GTK2.Entry compatibility.
//Do not provide a buffer; create this with no args, and if you need access to the buffer, call
//obj->get_buffer() separately. NOTE: This does not automatically scroll (a GTK2.Entry does). If
//you need scrolling, place this inside a GTK2.ScrolledWindow.
class MultiLineEntryField
{
	#if constant(GTK2.SourceView)
	inherit GTK2.SourceView;
	#else
	inherit GTK2.TextView;
	#endif
	this_program set_text(mixed ... args)
	{
		object buf=get_buffer();
		buf->begin_user_action(); //Permit undo of the set_text operation
		buf->set_text(@args);
		buf->end_user_action();
		return this;
	}
	string get_text()
	{
		object buf=get_buffer();
		return buf->get_text(buf->get_start_iter(),buf->get_end_iter(),0);
	}
	this_program set_position(int pos)
	{
		object buf=get_buffer();
		buf->place_cursor(buf->get_iter_at_offset(pos));
		return this;
	}
	int get_position()
	{
		object buf=get_buffer();
		return buf->get_iter_at_mark(buf->get_insert())->get_offset();
	}
	this_program set_visibility(int state)
	{
		#if !constant(COMPAT_NOPASSWD)
		object buf=get_buffer();
		(state?buf->remove_tag_by_name:buf->apply_tag_by_name)("password", buf->get_start_iter(), buf->get_end_iter());
		#endif
		return this;
	}
}

//GTK2.ComboBox designed for text strings. Has set_text() and get_text() methods.
//Should be able to be used like an Entry.
class SelectBox(array(string) strings)
{
	inherit GTK2.ComboBox;
	void create() {::create(""); foreach (strings,string str) append_text(str);}
	this_program set_text(string txt)
	{
		set_active(search(strings,txt));
		return this;
	}
	string get_text() //Like get_active_text() but will return 0 (not "") if nothing's selected (may not strictly be necessary, but it's consistent with entry fields and such)
	{
		int idx=get_active();
		return (idx>=0 && idx<sizeof(strings)) && strings[idx];
	}
	void set_strings(array(string) newstrings)
	{
		foreach (strings,string str) remove_text(0);
		foreach (strings=newstrings,string str) append_text(str);
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
		return win->stock_close=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_CLOSE]))
			->add_accelerator("clicked",stock_accel_group(),0xFF1B,0,0); //Esc as a shortcut for Close
	}

	//Stock item creation: Menu bar. Normally will want to be packed_start(,0,0,0) into a Vbox.
	GTK2.MenuBar stock_menu_bar(string ... menus)
	{
		win->stock_menu_bar = GTK2.MenuBar();
		win->menus = ([]); win->menuitems = ([]);
		foreach (menus, string menu)
		{
			string key = lower_case(menu) - "_"; //Callables to be placed in this menu start with this key.
			win->stock_menu_bar->add(GTK2.MenuItem(menu)->set_submenu(win->menus[key] = (object)GTK2.Menu()));
		}
		return win->stock_menu_bar;
	}

	//Stock "item" creation: AccelGroup. The value of this is that it will only ever create one.
	GTK2.AccelGroup stock_accel_group()
	{
		if (!win->accelgroup)
		{
			win->accelgroup = GTK2.AccelGroup();
			if (win->mainwindow) win->mainwindow->add_accel_group(win->accelgroup);
		}
		return win->accelgroup;
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
		if (win->stock_menu_bar)
		{
			multiset(string) seen = (<>);
			foreach (sort(indices(this_program)), string attr)
			{
				if (sscanf(attr, "menu_%s_%s", string menu, string item) && this[menu + "_" + item])
				{
					object m = win->menus[menu];
					if (!m) error("%s has no corresponding menu [try%{ %s%}]\n", attr, indices(win->menus));
					if (object old = win->menuitems[attr]) old->destroy();
					array|string info = this[attr];
					GTK2.MenuItem mi = arrayp(info)
						? GTK2.MenuItem(info[0])->add_accelerator("activate", stock_accel_group(), info[1], info[2], GTK2.ACCEL_VISIBLE)
						: GTK2.MenuItem(info); //String constants are just labels; arrays have accelerator key and modifiers.
					m->add(mi->show());
					win->signals += ({gtksignal(mi, "activate", this[menu + "_" + item])});
					win->menuitems[attr] = mi;
					seen[attr] = 1;
				}
			}
			//Having marked off everything we've added/updated, remove the left-overs.
			foreach (win->menuitems - seen; string key;)
				m_delete(win->menuitems, key)->destroy();
		}
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
	void create(string|void name)
	{
		if (name) sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) {if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;}
		win->self=this;
		if (!win->mainwindow) makewindow();
		if (is_subwindow) win->mainwindow->set_transient_for(win->_parentwindow || G->G->window->mainwindow);
		win->mainwindow->set_skip_taskbar_hint(is_subwindow)->set_skip_pager_hint(is_subwindow)->show_all();
		dosignals();
	}
	void showwindow()
	{
		if (!win->mainwindow) {makewindow(); dosignals();}
		win->mainwindow->set_no_show_all(0)->show_all();
	}
	int hidewindow()
	{
		win->mainwindow->hide();
		return 1; //Simplify anti-destruction as "return hidewindow()". Note that this can make updating tricky - be aware of this.
	}
	int closewindow()
	{
		win->mainwindow->destroy();
		destruct(win->mainwindow);
		return 1;
	}
}

//Subclass of window that handles save/load of position automatically.
class movablewindow
{
	inherit window;
	constant pos_key=0; //(string) Set this to the persist[] key in which to store and from which to retrieve the window pos
	constant load_size=0; //If set to 1, will attempt to load the size as well as position. (It'll always be saved.)
	constant provides=0;

	void makewindow()
	{
		if (array pos=persist[pos_key])
		{
			if (sizeof(pos)>3 && load_size) win->mainwindow->set_default_size(pos[2],pos[3]);
			win->x=1; call_out(lambda() {m_delete(win,"x");},1);
			win->mainwindow->move(pos[0],pos[1]);
		}
		::makewindow();
	}

	void sig_b4_mainwindow_configure_event()
	{
		if (!has_index(win,"x")) call_out(savepos,0.1);
		mapping pos=win->mainwindow->get_position(); win->x=pos->x; win->y=pos->y;
	}

	void savepos()
	{
		if (!pos_key) {werror("%% Assertion failed: Cannot save position without pos_key set!\n"); return;} //Shouldn't happen.
		mapping sz=win->mainwindow->get_size();
		persist[pos_key]=({m_delete(win,"x"),m_delete(win,"y"),sz->width,sz->height});
	}
}

//Base class for a configuration dialog. Permits the setup of anything where you
//have a list of keyworded items, can create/retrieve/update/delete them by keyword.
//It may be worth breaking out some of this code into a dedicated ListBox class
//for future reuse. Currently I don't actually need that for Gypsum, but it'd
//make a nice utility class for other programs.
//NOTE: This class may end up becoming the legacy compatibility class, with a new
//and simpler one (under a new name) being created, thus freeing current code from
//the baggage of backward compatibility - which this has a lot of. I could then
//deprecate this class (with no intention of removal) and start fresh.
class configdlg
{
	inherit window;
	//Provide me...
	mapping(string:mixed) windowprops=(["title":"Configure"]);
	mapping(string:mapping(string:mixed)) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping, or something out of persist[] (and see persist_key)
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword.
	string actionbtn; //(DEPRECATED) If set, a special "action button" will be included, otherwise not. This is its caption.
	void action_callback() { } //(DEPRECATED) Callback when the action button is clicked (provide if actionbtn is set)
	constant allow_new=1; //Set to 0 to remove the -- New -- entry; if omitted, -- New -- will be present and entries can be created.
	constant allow_delete=1; //Set to 0 to disable the Delete button (it'll always be visible though)
	constant allow_rename=1; //Set to 0 to ignore changes to keywords
	constant strings=({ }); //Simple string bindings - see plugins/README
	constant ints=({ }); //Simple integer bindings, ditto
	constant bools=({ }); //Simple boolean bindings (to CheckButtons), ditto
	constant labels=({ }); //Labels for the above
	/* PROVISIONAL: Instead of using all of the above four, use a single list of
	tokens which gets parsed out to provide keyword, label, and type.
	constant elements=({"kwd:Keyword", "name:Name", "?state:State of Being", "#value:Value","+descr:Description"});
	If the colon is omitted, the keyword will be the first word of the lowercased name, so this is equivalent:
	constant elements=({"kwd:Keyword", "Name", "?State of Being", "#Value", "+descr:Description"});
	In most cases, this and persist_key will be all you need to set.
	Still figuring out a good way to allow a SelectBox. Currently messing with "@name:lbl",({opt,opt,opt}) which
	is far from ideal.
	This is eventually going to be the primary way to do things, but it's currently unpledged to permit changes.
	In fact, I'd say that it's _now_ (20160809) the primary way to do things, but I haven't yet deprovisionalized
	it in case I want to make changes (esp to the SelectBox and Notebook APIs). There's already way too much
	cruft in this class to risk letting even more in.
	*/
	constant elements=({ });
	constant persist_key=0; //(string) Set this to the persist[] key to load items[] from; if set, persist will be saved after edits.
	constant descr_key=0; //(string) Set this to a key inside the info mapping to populate with descriptions.
	string selectme; //If this contains a non-null string, it will be preselected.
	//... end provide me.
	mapping defaults = ([]); //TODO: Figure out if any usage of defaults needs the value to be 'put back', or not be a string, or anything.

	void create(string|void name)
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

	void sig_sel_changed()
	{
		string kwd=selecteditem();
		mapping info=items[kwd] || ([]);
		if (win->kwd) win->kwd->set_text(kwd || "");
		foreach (win->real_strings,string key) win[key]->set_text((string)(info[key] || defaults[key] || ""));
		foreach (win->real_ints,string key) win[key]->set_text((string)(info[key] || defaults[key]));
		foreach (win->real_bools,string key) win[key]->set_active((int)info[key]);
		load_content(info);
	}

	void makewindow()
	{
		win->real_strings = strings; win->real_ints = ints; win->real_bools = bools; //Migrate the constants
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
					->add(win->list=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
						->append_column(GTK2.TreeViewColumn("Item",GTK2.CellRendererText(),"text",0))
						->append_column(GTK2.TreeViewColumn("",GTK2.CellRendererText(),"text",1))
					)
					->add(GTK2.Vbox(0,0)
						->add(make_content())
						->pack_end(
							(actionbtn?GTK2.HbuttonBox()
							->add(win->pb_action=GTK2.Button((["label":actionbtn,"use-underline":1])))
							:GTK2.HbuttonBox())
							->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
							->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1,"sensitive":allow_delete])))
						,0,0,0)
					)
				)
				->add(win->buttonbox=GTK2.HbuttonBox()->pack_end(stock_close(),0,0,0))
			);
		win->sel=win->list->get_selection(); win->sel->select_iter(win->new_iter||ls->get_iter_first()); sig_sel_changed();
		::makewindow();
		if (stringp(selectme)) select_keyword(selectme) || (win->kwd && win->kwd->set_text(selectme));
	}

	//Generate a widget collection from either the constant or migration mode
	array(string|GTK2.Widget) collect_widgets(array|void elem, int|void noreset)
	{
		array objects = ({ });
		//Clear the arrays only if we're not recursing.
		if (!noreset) win->real_strings = win->real_ints = win->real_bools = ({ });
		elem = elem || elements; if (!sizeof(elem)) elem = migrate_elements();
		string next_obj_name = 0;
		foreach (elem, mixed element)
		{
			if (next_obj_name)
			{
				if (arrayp(element))
					objects += ({win[next_obj_name] = SelectBox(element)});
				else
					error("Assertion failed: SelectBox without element array\n");
				next_obj_name = 0;
				continue;
			}
			if (mappingp(element))
			{
				//EXPERIMENTAL: A mapping creates a notebook.
				object nb = GTK2.Notebook();
				foreach (sort(indices(element)), string tabtext)
					nb->append_page(
						//Tab contents: Recursively collect widgets from the given array.
						two_column(collect_widgets(element[tabtext], 1)),
						//Tab text comes from the mapping key.
						GTK2.Label(tabtext)
					);
				objects += ({nb, 0});
				continue;
			}
			sscanf(element, "%1[?#+'@!*]%s", string type, element);
			sscanf(element, "%s=%s", element, string dflt); //NOTE: I'm rather worried about collisions here. This is definitely PROVISIONAL.
			sscanf(element, "%s:%s", string name, string lbl);
			if (!lbl) sscanf(lower_case(lbl = element)+" ", "%s ", name);
			if (dflt) defaults[name] = dflt;
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
				case "*": //Password
					win->real_strings += ({name});
					objects += ({lbl, win[name]=noex(GTK2.Entry())});
					if (type == "*") win[name]->set_visibility(0);
					break;
				case "+": //Multi-line text
					win->real_strings += ({name});
					objects += ({GTK2.Frame(lbl)->add(
						win[name]=MultiLineEntryField()->set_wrap_mode(GTK2.WRAP_WORD_CHAR)->set_size_request(225,70)
					),0});
					break;
				case "'": //Descriptive text
				{
					//Names apply to labels only if they consist entirely of lower-case ASCII letters.
					//Otherwise, the label has no name (even if it contains a colon).
					sscanf(element, "%[a-z]:%s", string lblname, string lbltext);
					//This looks a little odd, but it does work. If parsing is successful, we have
					//a name to save under; otherwise, sscanf will have put the text into lblname,
					//so we use that as the label *text*, and it has no name.
					object obj = noex(GTK2.Label(lbltext || element)->set_line_wrap(1));
					objects += ({obj, 0});
					if (lbltext) win[lblname] = obj;
					break;
				}
				case "@": //Drop-down
				{
					//Special case: Integer drop-downs are marked with "@#".
					if (name[0] == '#') win->real_ints += ({name=name[1..]});
					else win->real_strings += ({name});
					objects += ({lbl}); next_obj_name = name; //Object creation happens next iteration
					break;
				}
				case "!": //Button
				{
					//Buttons don't get any special load/save action.
					//Normally you'll attach a clicked event to them.
					//TODO: Put consecutive button elements into the same button box
					objects += ({GTK2.HbuttonBox()->add(win[name] = GTK2.Button((["label": lbl, "use-underline": 1]))), 0});
					break;
				}
			}
		}
		win->real_strings -= ({"kwd"});
		return objects;
	}

	//Iterates over labels, applying them to controls in this order:
	//1) win->kwd, if allow_rename is not zeroed
	//2) strings, creating Entry()
	//3) ints, ditto
	//4) bools, creating CheckButton()
	//5) strings, if marked to create MultiLineEntryField()
	//6) Descriptive text underneath
	//Not yet supported: Anything custom, eg insertion or reordering;
	//any other widget types eg SelectBox.
	array(string) migrate_elements()
	{
		array stuff = ({ });
		array atend = ({ });
		Iterator lbl = get_iterator(labels);
		if (!lbl) return stuff;
		if (allow_rename)
		{
			stuff += ({"kwd:"+lbl->value()});
			if (!lbl->next()) return stuff;
		}
		foreach (strings+ints, string name)
		{
			string desc=lbl->value();
			if (desc[0]=='\n') //Hack: Multiline fields get shoved to the end. Hack is not needed if elements[] is used instead - this is recommended.
				atend += ({sprintf("+%s:%s",name,desc[1..])});
			else
				stuff += ({sprintf("%s:%s",name,desc)});
			if (!lbl->next()) return stuff+atend;
		}
		foreach (bools, string name)
		{
			stuff += ({sprintf("?%s:%s",name,lbl->value())});
			if (!lbl->next()) return stuff+atend;
		}
		stuff += atend; //Now grab any multiline string fields
		//Finally, consume the remaining entries making text. There'll most
		//likely be zero or one of them.
		foreach (lbl;;string text)
			stuff += ({"'"+text});
		return stuff;
	}

	//Create and return a widget (most likely a layout widget) representing all the custom content.
	//If allow_rename (see below), this must assign to win->kwd a GTK2.Entry for editing the keyword;
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or
	//it may be a GTK2.Label, or it may be omitted altogether).
	//By default, makes a two_column based on collect_widgets. It's easy to override this to add some
	//additional widgets before or after the ones collect_widgets creates.
	GTK2.Widget make_content()
	{
		return two_column(collect_widgets());
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

	void dosignals()
	{
		::dosignals();
		if (actionbtn) win->signals+=({gtksignal(win->pb_action,"clicked",action_callback)});
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

	mapping(string:mixed) mi=([]);
	void create(string|void name)
	{
		if (!name) return;
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (object old=G->G->menuitems[name]) old->destroy();
		object mi = GTK2.MenuItem(menu_label);
		G->G->windows->mainwindow->optmenu->add(mi->show());
		mi->signal_connect("activate",menu_clicked);
		G->G->menuitems[name] = mi;
	}
}

class ircsettings
{
	//Full control but less convenient
	inherit window;
	mapping config = persist->path("ircsettings");

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Authenticate StilleBot"]))->add(two_column(({
			win->open_auth=GTK2.Button("Open http://twitchapps.com/tmi/"),0,
			"Twitch user name", win->nick=GTK2.Entry()->set_text(config->nick||""),
			"Real name (optional)", win->realname=GTK2.Entry()->set_text(config->realname||""),
			"OAuth2 key", win->pass=GTK2.Entry()->set_visibility(0),
			GTK2.Label("Key will not be shown above. Obtain"),0,
			GTK2.Label("one from twitchapps and paste it in."),0,
			GTK2.HbuttonBox()
				->add(win->save=GTK2.Button("Save"))
				->add(stock_close())
			,0
		})));
	}

	void sig_open_auth_clicked()
	{
		invoke_browser("http://twitchapps.com/tmi/");
	}

	void sig_save_clicked()
	{
		config->nick = win->nick->get_text();
		config->realname = win->realname->get_text();
		string pass = win->pass->get_text();
		if (has_prefix(pass, "oauth:")) config->pass = pass;
		persist->save();
		closewindow();
		if (!G->G->irc) G->bootstrap_all(); //Force an update to get us connected.
	}
}

class easy_auth
{
	//The simple, normal way to authenticate
	inherit window;
	mapping config = persist->path("ircsettings");
	//TODO: Generate our own, probably using a github.io redirect URI
	constant url = "https://api.twitch.tv/kraken/oauth2/authorize?response_type=token&client_id=q6batx0epp608isickayubi39itsckt&redirect_uri=https://twitchapps.com/tmi/&scope=chat_login+user_read";

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Authenticate with Twitch"]))->add(GTK2.Vbox(0, 10)
			->add(GTK2.Entry()->set_text(url)->set_editable(0))
			->add(win->open_auth=GTK2.Button("Open in web browser"))
			->add(GTK2.Hbox(0, 10)
				->add(GTK2.Label("OAuth2 key"))
				->add(win->pass=GTK2.Entry()->set_visibility(0))
			)
			->add(win->check=GTK2.Button("Paste your key above")->set_sensitive(0))
			->add(GTK2.HbuttonBox()
				->add(win->save=GTK2.Button("Save")->set_sensitive(0))
				->add(stock_close())
			)
		);
	}

	void sig_open_auth_clicked() {invoke_browser(url);}

	void sig_pass_changed()
	{
		if (win->pass->get_text() == "") win->check->set_sensitive(0)->set_label("Paste your key above");
		else win->check->set_sensitive(1)->set_label("Check key");
	}

	void data_available(object q, string pass)
	{
		mixed data = Standards.JSON.decode(q->unicode_data());
		if (data->error || !data->name) {win->check->set_label("Error checking key"); return;}
		win->check->set_label("Checked OK");
		win->nick = data->name; win->realname = data->display_name; win->oauth = pass;
		win->save->set_sensitive(1)->set_label("Save: "+data->display_name);
	}
	void request_ok(object q, string pass) {q->async_fetch(data_available, pass);}
	void request_fail(object q, string pass) { }

	void sig_check_clicked()
	{
		win->check->set_sensitive(0)->set_label("Checking...");
		sscanf(win->pass->get_text(), "oauth:%s", string pass);
		if (!pass) return;
		Protocols.HTTP.do_async_method("GET", "https://api.twitch.tv/kraken/user", 0,
			(["Authorization": "OAuth " + pass]),
			Protocols.HTTP.Query()->set_callbacks(request_ok, request_fail, pass));
	}

	void sig_save_clicked()
	{
		if (!win->oauth) return; //Shouldn't happen (button is disabled till it's set)
		mapping config = persist->path("ircsettings");
		config->nick = win->nick;
		config->realname = win->realname;
		config->pass = win->oauth;
		persist->save();
		closewindow();
		if (!G->G->irc) G->bootstrap_all(); //Force an update to get us connected.
	}
}

class whisper_participants(string chan, int limit, int followersonly)
{
	inherit window;
	void create() {::create();}

	void makewindow()
	{
		win->mainwindow = GTK2.Window((["title": "Whisper to chat participants"]))->add(GTK2.Vbox(0, 10)
			->add(GTK2.Label("Whisper to participants for " + chan))
			->add(GTK2.Hbox(0, 10)
				->pack_start(GTK2.Label("Message:"), 0, 0, 0)
				->add(win->msg = GTK2.Entry())
			)
			->add(win->people = GTK2.Table(1, 1, 0))
			->add(GTK2.HbuttonBox()
				->add(win->refresh = GTK2.Button("Refresh"))
				->add(win->shuffle = GTK2.Button("Shuffle"))
				->add(stock_close())
			)
		);
		sig_refresh_clicked();
	}

	void sig_refresh_clicked() {redraw(0);}
	void sig_shuffle_clicked() {redraw(1);}
	void redraw(int sortmode)
	{
		mapping userinfo = G_G_("participants", chan);
		array prev = win->people->get_children();
		prev->destroy(); destruct(prev[*]);
		array(string) users = indices(userinfo);
		if (sortmode) Array.shuffle(users);
		//TODO: Sort them by earliest comment/notice for sortmode 2?
		int pos = 0;
		foreach (users, string user)
		{
			mapping info = userinfo[user];
			int since = time() - info->lastnotice;
			if (since > limit) continue;
			string msg;
			if (!info->following)
			{
				if (followersonly) continue;
				msg = user;
			}
			else msg = sprintf("%s (following %s)", user, (info->following/"T")[0]);
			object btn = GTK2.Button(msg)->show();
			int row = pos/4, col = pos%4; ++pos;
			win->people->attach(btn, col, col+1, row, row+1, 0, 0, 1, 1);
			btn->signal_connect("clicked", send_whisper, user);
		}
	}

	void send_whisper(object self, string user)
	{
		send_message("#" + chan, "/w " + user + " " + win->msg->get_text());
	}
}

object mainwindow;
class _mainwindow
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title": "StilleBot"]);
	constant elements=({"kwd:Channel", "?allcmds:All commands active", "+notes:Notes", "'uptime:", ([
		"\"Notice Me!\"": ({"'Let chat participants get your attention.", "?noticechat:Enabled", "?Followers only", "NoticeMe keyword", "#Timeout (within X sec)=600", "!Whisper to participants"}),
		"Channel currency": ({"Currency name", "#Payout interval", "#payout_offline:Offline divisor [0 for none]", "#payout_mod:Mod multiplier"}),
		"Logging": ({"?chatlog:Log chat to console", "?countactive:Count participant activity"}),
		"Song requests": ({"?songreq:Active", "#songreq_length:Max length (seconds)"}),
	])});
	constant persist_key = "channels";
	constant is_subwindow = 0;
	void create() {::create("mainwindow"); remake_content(); mainwindow = win->mainwindow;}

	void makewindow()
	{
		::makewindow();
		//Add a menu bar. This is a bit of a hack.
		object vbox = win->mainwindow->get_child();
		object menubar = GTK2.MenuBar()
			->add(GTK2.MenuItem("_Options")->set_submenu(win->optmenu=GTK2.Menu()
				->add(win->update=GTK2.MenuItem("Update (developer mode)"))
				->add(win->authenticate=GTK2.MenuItem("Change Twitch user"))
				->add(win->manual_auth=GTK2.MenuItem("Authenticate manually"))
			));
		vbox->pack_start(menubar,0,0,0)->reorder_child(menubar, 0);
		//Remove the close button - we don't need it.
		//(You can still click the cross or press Alt-F4 or anything else.)
		win->buttonbox->remove(win->stock_close);
		destruct(win->stock_close);
	}

	void sig_kwd_changed(object self)
	{
		string txt = self->get_text();
		string lc = lower_case(txt);
		if (lc != txt) self->set_text(lc);
	}
	function sig_noticeme_changed = sig_kwd_changed;

	//This allows updating of the content block in a live configdlg.
	//Downside: It probably *only* works (reliably) with the new 'elements'
	//system; no guarantees about all the older ways of doing things. So
	//it's not currently a core feature, and upstream Gypsum doesn't have it
	//at all. Eventually, a new and not-backward-compatible configdlg may be
	//created, with a new name, and it can have this kind of feature. (It
	//needn't actually break active stuff - it'll just drop support for all
	//the old and deprecated things, like the action button.)
	//Also, this can't adequately handle removal/renaming of objects. There's
	//no guarantee that the old objects will be destroyed; in fact, they'll
	//probably hang around in win[].
	GTK2.Widget make_content() {return win->contentblock = ::make_content();}
	void remake_content()
	{
		object parent = win->contentblock->get_parent();
		parent->remove(win->contentblock);
		//win->contentblock->destroy();
		parent->add(make_content()->show_all());
		dosignals(); //For some reason, updating code redoes signals BEFORE triggering this.
		sig_sel_changed();
	}

	void sig_update_activate(object self)
	{
		int err = G->bootstrap_all();
		if (!err) return; //All OK? Be silent.
		if (string winid = getenv("WINDOWID")) //On some Linux systems we can pop the console up.
			catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait()); //Try, but don't mind errors, eg if wmctrl isn't installed.
		MessageBox(0, GTK2.MESSAGE_ERROR, GTK2.BUTTONS_OK, err + " compilation error(s) - see console", win->mainwindow);
	}

	void sig_authenticate_activate() {easy_auth();}
	void sig_manual_auth_activate() {ircsettings();}

	void save_content(mapping(string:mixed) info)
	{
		string kwd = win->kwd->get_text();
		if (object chan=G->G->irc->channels["#"+kwd])
		{
			write("%%% Saving data for #"+kwd+"\n");
			chan->save();
		}
		else
		{
			write("%%% Joining #"+kwd+"\n");
			G->G->irc->join_channel("#"+kwd);
		}
	}
	void load_content(mapping(string:mixed) info)
	{
		if (string kwd = selecteditem())
		{
			string host = "";
			if (object chan=G->G->irc->channels["#"+kwd])
				if (chan->hosting) host = "Hosting: " + chan->hosting;
			win->uptime->set_text(channel_uptime(kwd) || host);
		}
	}
	void delete_content(string kwd,mapping(string:mixed) info)
	{
		write("%%% Parting #"+kwd+"\n");
		G->G->irc->part_channel("#"+kwd);
	}

	void sig_whisper_clicked()
	{
		string chan = selecteditem();
		if (!chan) return;
		whisper_participants(chan, (int)win->timeout->get_text() || 600, win->followers->get_active());
	}

	void closewindow() {exit(0);}
}

void create(string name)
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
	if (G->G->menuitems) values(G->G->menuitems)->destroy();
	G->G->menuitems = ([]);
	_mainwindow();
	if (!persist["ircsettings"]) easy_auth();
}
