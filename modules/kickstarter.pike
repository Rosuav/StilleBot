__async__ void pingkickstarter() {
	G->G->kickstarter_call_out = call_out(pingkickstarter, 30);
	object res = await(Protocols.HTTP.Promise.get_url("https://www.kickstarter.com/projects/buriedcandy/the-calling-1/stats.json?v=1"));
	mapping project = Standards.JSON.decode(res->get())->project;
	object channel = G->G->irc->channels["#buriedcandy"];
	channel->set_variable("backedamount", (string)project->pledged);
	if (channel->expand_variables("$backers$") != (string)project->backers_count) {
		channel->set_variable("backers", (string)project->backers_count);
		channel->send((["user": "buriedcandy"]), "Woohoo! We now have $backers$ backers for a total of $backedamount$!");
	}
}

protected void create(string name) {
	remove_call_out(G->G->kickstarter_call_out);
	if (is_active_bot()) G->G->kickstarter_call_out = call_out(pingkickstarter, 60);
}
