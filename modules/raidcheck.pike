inherit command;
constant require_moderator = 1;
constant hidden_command = 1;

echoable_message process(object channel, mapping person, string param) {
	if (param == "") return "@$$: !raidcheck otherusername";
	Concurrent.all(get_user_id(channel->name[1..]), get_user_id(param))->then(lambda(array(int) ids) {
		[int fromid, int toid] = ids;
		channel->send(person, sprintf("Raids between %O (%O) and %O (%O)", channel->name[1..], fromid, param, toid));
		int outgoing = fromid < toid;
		string base = outgoing ? (string)fromid : (string)toid;
		string other = outgoing ? (string)toid : (string)fromid;
		void report(array raids, string tag) {
			if (raids) {
				channel->send(person, sprintf("Have %d raids in the %s log", sizeof(raids), tag));
				foreach (raids, mapping r) if (r->time > time()) {
					channel->send(person, "FUTURE RAID - see console");
					werror("FUTURE RAID: %O\n", r);
				}
			}
		}
		report(persist_status->path("raids")[base][?other], "correct");
		report(persist_status->path("raids")[other][?base], "incorrect");
	});
	return "Checking...";
}
