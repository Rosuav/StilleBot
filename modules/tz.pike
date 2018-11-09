//Note that this is currently aimed somewhat at CookingForNoobs, with its timezone conversions.
//TODO: Make the target timezone per-channel customizable.
//TODO: Return an array instead of depending on wrap
inherit command;
constant all_channels = 1;

mapping timezones;
mapping(string:string) tzleaf;

constant days_of_week = ({"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"});

//Like String.sillycaps but splitting on underscores, so broken_hill becomes Broken_Hill
string capitalize(string timezone)
{
	return String.capitalize((timezone/"_")[*])*"_";
}

string timezone_info(string tz)
{
	if (!tz || tz=="") return "Regions are: " + capitalize(sort(indices(timezones))[*])*", " +
		". You can also add a weekday and time, eg '!tz America/Los_Angeles Thu 10:00'. Type '!tz help' for " +
		"more info, or '!tz common' for some common timezones.";
	if (tz == "help") return "Hi! I'm a timezone-converting bot. You can inquire about the current time in any of the " +
		sizeof(Calendar.TZnames.zonenames()) + " timezones that I'm familiar with; to do this, simply type '!tz " +
		random(Calendar.TZnames.zonenames()) + "' or '!tz " + (random(Calendar.TZnames.zonenames())/"/")[-1] + "'. You can also " +
		"convert times from your timezone into Christine's, by typing '!tz " + random(Calendar.TZnames.zonenames()) +
		" " + random(days_of_week)[..2] + " " + random(24) + ":00', with am/pm times also supported.";
	if (tz == "common") return "US timezones are Los_Angeles, Denver, Chicago, New_York, Hawaii, and Anchorage. Most geographically-small " +
		"countries operate on a single timezone, identified by the capital, such as Europe/London for the UK, or Istanbul for Turkey. " +
		"Asia/Kathmandu is a quarter-hour timezone, and Australia/Sydney and Australia/Melbourne differ only in DST. Have fun. :)";
	sscanf(tz, "%s %s", tz, string time);
	tz = tzleaf[lower_case(tz)] || tz; //If you enter "Melbourne", use "Australia/Melbourne" automatically.
	mapping|string region = timezones;
	foreach (lower_case(tz)/"/", string part) if (!mappingp(region=region[part])) break;
	if (undefinedp(region))
		return "Unknown region "+tz+" - use '!tz' to list";
	if (mappingp(region))
		return "Locations in region " + tz + ": " + capitalize(sort(indices(region))[*])*", ";
	if (catch {
		if (!time) return region+" - "+Calendar.Gregorian.Second()->set_timezone(region)->format_time();
		string ret = "";
		foreach (({({region, "America/Los_Angeles", "%s %s in your time is %s %s in Christine's. "}),
			({"America/Los_Angeles", region, "%s %s in Christine's time is %s %s in yours."})}),
			[string tzfrom, string tzto, string msg])
		{
			sscanf(time, "%s %s", string dayname, string time); dayname = lower_case(dayname);
			int dow = -1;
			foreach (days_of_week; int idx; string d) if (has_prefix(lower_case(d), dayname)) dow = idx;
			Calendar.Gregorian.Day day = Calendar.Gregorian.Day()->set_timezone(tzfrom);
			sscanf(time, "%d:%d%s", int hr, int min, string ampm);
			if (!min) sscanf(time, "%d%s", hr, ampm); //Catch "6pm" correctly
			if ((<"PM","pm">)[ampm]) hr+=12;
			if (!hr) hr = (int)time;
			Calendar.Gregorian.Second tm = day->second(3600*hr+60*min);
			if (int diff=hr-tm->hour_no()) tm=tm->add(3600*diff); //If DST switch happened, adjust time
			if (int diff=min-tm->minute_no()) tm=tm->add(60*diff);
			if (int diff=0-tm->second_no()) tm=tm->add(60*diff); //As above but since sec will always be zero, hard-code it.
			tm = tm->set_timezone(tzto);
			int daydiff = 0;
			if (tm->day() > day) daydiff = 1;
			else if (tm->day() < day) daydiff = -1;
			ret += sprintf(msg, days_of_week[dow], time, days_of_week[(dow+daydiff) % 7], tm->nice_print());
		}
		return ret;
	}) return "Unable to figure out the time in that location, sorry.";
}

string process(object channel, object person, string param)
{
	if (channel->config->allcmds /*|| channel->name == "#cookingfornoobs"*/)
		//TODO: Have a generic way to choose which commands something's open in.
		//Possibly by configuring the default timezone???
		return "@$$: " + timezone_info(param);
}

string default_time(object channel, object person, string param)
{
	return check_perms(channel, person, "America/Los_Angeles");
}

void create(string name)
{
	timezones = ([]); tzleaf = ([]);
	foreach (sort(Calendar.TZnames.zonenames()), string zone)
	{
		array(string) parts = lower_case(zone)/"/";
		mapping tz = timezones;
		foreach (parts[..<1], string region)
			if (!tz[region]) tz = tz[region] = ([]);
			else tz = tz[region];
		tz[parts[-1]] = zone;
		if (tzleaf[parts[-1]]) werror("%s\n", tzleaf[parts[-1]] = "ASSERT FAILED - duplicate leaf node " + tzleaf[parts[-1]] + " and " + zone);
		else tzleaf[parts[-1]] = zone;
	}
	::create(name);
	G->G->commands["time"] = default_time;
}
