//Track active threads
inherit menu_item;

void thread_watch(object ls) {
	mapping threads = ([]);
	object tm = System.Timer();
	while (G->G->ticker_active) {
		float total = tm->peek() * 1000000.0; // usec
		foreach (Thread.all_threads(), object t) {
			int id = t->id_number();
			array th = threads[id];
			if (!th) {
				object iter = ls->append();
				ls->set_value(iter, 0, sprintf("0x%x", id));
				threads[id] = th = ({iter, t->gethrvtime(), ([])});
			}
			[object iter, int basetime, mapping hotspots] = th;
			int usec = t->gethrvtime() - basetime;
			float prop = 100.0 * usec / total;
			ls->set_value(iter, 1, sprintf("%%%.3f", prop));
			string location;
			//Find the last plausible backtrace entry
			foreach (t->backtrace(), object f) {
				if (f->filename && f->filename != "-" && f->filename[0] != '/')
					location = sprintf("%s:%d", f->filename, f->line);
			}
			if (location) hotspots[location]++;
			ls->set_value(iter, 2, location || "(unknown)");
		}
		sleep(0.125);
	}
	foreach (threads; int id; array info) {
		write("Thread 0x%d:\n", id);
		array hotspots = indices(info[2]); sort(values(info[2]), hotspots);
		foreach (reverse(hotspots)[..16], string loc)
			write("\t%4d %s\n", info[2][loc], loc);
	}
}

constant menu_label = "Show threads";
class menu_clicked
{
	inherit window;
	constant is_subwindow = 0;
	protected void create() {::create();}

	void makewindow()
	{
		object ls = win->store = GTK2.ListStore(({"string", "string", "string"}));
		G->G->ticker_active = 1;
		Thread.Thread(thread_watch, ls);
		win->mainwindow = GTK2.Window((["title": "Running threads"]))->add(GTK2.Vbox(0,0)
			->add(win->list = GTK2.TreeView(ls)
				->append_column(GTK2.TreeViewColumn("TID", GTK2.CellRendererText(), "text", 0))
				->append_column(GTK2.TreeViewColumn("Time", GTK2.CellRendererText(), "text", 1))
				->append_column(GTK2.TreeViewColumn("Location", GTK2.CellRendererText(), "text", 2))
			)->pack_start(GTK2.HbuttonBox()->add(GTK2.Button("Update"))->add(stock_close()), 0, 0, 0)
		);
	}
	int closewindow() {G->G->ticker_active = 0; ::closewindow();}
}

protected void create(string name) {
	::create(name);
	G->G->ticker_active = 0;
}
