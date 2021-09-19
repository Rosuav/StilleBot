inherit builtin_command;
constant featurename = 0; //TODO: Make a default-ish command with a proper feature-enabler?

mapping timezones;
mapping(string:string) tzleaf;

constant command_description = "Show the current time in a particular, or your default, timezone";
constant builtin_description = "Get the current date and time in a particular timezone"; //TODO: Or convert date/time
constant builtin_name = "Date/Time";
constant builtin_param = "Timezone name"; //TODO: And optional date
constant default_response = "";
constant vars_provided = ([
	"{tz}": "Timezone in canonical form eg Australia/Melbourne",
	"{unix}": "Unix time right now", //TODO: Or the date/time converted
	"{year}": "Date in specified timezone: Year (4 digits)",
	"{month}": "Date in specified timezone: Month (2 digits)",
	"{day}": "Date in specified timezone: Day (2 digits)",
	"{hour}": "Time in specified timezone: Hour (2 digits)",
	"{minute}": "Time in specified timezone: Minute (2 digits)",
	"{second}": "Time in specified timezone: Second (2 digits)",
	"{weekday}": "Weekday name (in English, full word, eg 'Monday')",
	"{weekday_short}": "Weekday name (in English, abbr, eg 'Mon')",
]);

mapping message_params(object channel, mapping person, string param)
{
	write("GET PARAMS: %O\n", param);
	string tz = replace(param, " ", "_");
	tz = tzleaf[lower_case(tz)] || tz; //If you enter "Melbourne", use "Australia/Melbourne" automatically.
	object t = Calendar.Gregorian.Second()->set_timezone(tz);
	mapping info = (["{tz}": tz, "{unix}": t->unix_time()]);
	foreach ("year month hour minute second" / " ", string twodigit) //Yes, year too, since a four digit number will still render correctly
		info["{" + twodigit + "}"] = sprintf("%02d", t[twodigit + "_no"]());
	info["{day}"] = sprintf("%02d", t->month_day());
	info["{weekday}"] = t->week_day_name();
	info["{weekday_short}"] = t->week_day_shortname();
	return info;
}

protected void create(string name)
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
}
