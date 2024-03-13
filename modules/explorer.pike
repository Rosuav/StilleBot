//Pop up a window to explore global state. Start with G or G->G, and drill down as far as you want.
inherit menu_item;

constant menu_label = "Explore StilleBot's internals";
class menu_clicked
{
	inherit window;
	constant windowtitle = "Explore StilleBot internals";
	protected void create() {::create();}

	multiset(int) no_recursion = (<>);
	void add_to_store(mixed thing, string|void name, GTK2.TreeIter|void parent)
	{
		GTK2.TreeIter row = win->store->append(parent);
		if (name) name += ": "; else name = "";
		//Figure out how to represent the 'thing'.
		//Firstly, if we've already seen it, put a marker - don't
		//infinitely recurse.
		int hash = hash_value(thing); //Snapshot the hash - we may reassign 'thing' for convenience
		if (no_recursion[hash])
		{
			win->store->set_value(row, 0, name + "[recursive]");
			return;
		}
		no_recursion[hash] = 1;
		//Next up: Recognized types of nested structures.
		if (arrayp(thing) || multisetp(thing))
		{
			win->store->set_value(row, 0, sprintf("%s%t (%d)", name, thing, sizeof(thing)));
			thing = (array)thing;
			foreach (thing[..199], mixed subthing)
				add_to_store(subthing, 0, row);
			if (sizeof(thing) > 200)
				win->store->set_value(win->store->append(row), 0,
					sprintf("... %d more entries...", sizeof(thing)-100));
		}
		else if (mappingp(thing))
		{
			win->store->set_value(row, 0, sprintf("%smapping (%d)", name, sizeof(thing)));
			int count = 0;
			foreach (sort(indices(thing)), mixed key)
			{
				if (functionp(thing[key])) continue; //Ignore some uninteresting things stashed in G->G
				add_to_store(thing[key], stringp(key) ? key : sprintf("%O", key), row);
				if (++count >= 200) break;
			}
			if (sizeof(thing) > count)
				win->store->set_value(win->store->append(row), 0,
					sprintf("... %d more entries...", sizeof(thing)-count));
		}
		//Finally, non-nesting objects.
		else
		{
			if (!stringp(thing)) thing = sprintf("%O", thing);
			if (sizeof(thing) >= 256)
			{
				//Abbreviate it some
				win->store->set_value(row, 0, name + thing[..250] + "...");
				GTK2.TreeIter full = win->store->append(row);
				win->store->set_value(full, 0, thing);
			}
			else win->store->set_value(row, 0, name + thing);
		}
		no_recursion[hash] = 0;
	}

	void makewindow()
	{
		win->store = GTK2.TreeStore(({"string"}));
		//Ephemeral - discarded on program restart. Survives code reload.
		add_to_store(G->G, "G");
		//Database configuration. Shared between instances, can update live. Note that
		//precached config is not separated out here; it may be nice to at least annotate
		//which ones are PCC and which are not, but for now they're just in together.
		G->G->DB->generic_query("select * from stillebot.config")->then() {
			//Remap to a mapping, simpler than reimplementing parts of add_to_store
			mapping dbcfg = ([]);
			foreach (__ARGS__[0], mapping cfg) dbcfg[cfg->keyword] |= ([cfg->twitchid: cfg->data]);
			//Special case: If the only twitchid for a keyword is 0, it's probably one where users
			//are not part of the keying, so remove the unnecessary indirection level.
			foreach (dbcfg; string keyword; mapping users)
				if (sizeof(users) == 1 && users[0]) dbcfg[keyword] = users[0];
			add_to_store(dbcfg, "stillebot.config");
		};
		win->mainwindow=GTK2.Window((["title":"Explore StilleBot internals"]))->add(GTK2.Vbox(0,0)
			->add(GTK2.ScrolledWindow()
				->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_AUTOMATIC)
				->add(win->treeview=GTK2.TreeView(win->store)->set_size_request(400,250)
					->append_column(GTK2.TreeViewColumn("",GTK2.CellRendererText(),"text",0))
				)
			)
			->pack_start(GTK2.HbuttonBox()->add(stock_close()), 0, 0, 0)
		);
	}
}
