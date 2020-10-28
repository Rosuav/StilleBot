int main(int argc, array(string) argv)
{
	mapping sta = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_status.json"));
	if (!mappingp(sta)) exit(1, "No status found");
	foreach (argv[1..], string name)
	{
		mapping seen = sta->uid_to_name[sta->name_to_uid[name]];
		if (!seen) {write(name + ": Not found\n"); continue;} //Since uid_to_name[0] is 0, this is safe
		if (sizeof(seen) == 1 && seen[name]) {write(name + ": No others seen\n"); continue;}
		array names = indices(seen), times = values(seen);
		sort(times, names);
		write(name + ": " + names * ", " + "\n");
	}
}
