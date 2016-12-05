inherit command;
constant require_allcmds = 1;

int rogue_hp = 0;

string process(object channel, object person, string param)
{
	if (channel->mods[person->user])
	{
		if (param == "start")
		{
			rogue_hp = 1000;
			return "The [fake] Grey Game is starting!";
		}
		//Fall through to docs
	}
	return "This is the [fake] Grey Game. Documentation would go here.";
}

class attack(int power, int success, int fail, int lowcost, int highcost, string name, string msg)
{
	inherit command;
	constant require_allcmds = 1;
	void create() {::create(name);}
	mapping(string:int) cooldown = ([]);

	string process(object channel, object person, string param)
	{
		if (rogue_hp <= 0) return 0; //Game not active

		int t = time();
		int cd = cooldown[person->user] - t;
		if (cd > 0) return "@$$: Still cooling down! Wait another " + cd + " seconds.";
		cooldown[person->user] = t + 60;

		if (name == "assassinate")
		{
			//The rules for assassination are different.
			if (rogue_hp >= 100) return "@$$: You can't assassinate yet!";
		}
		else
		{
			if (rogue_hp < 100) return "@$$: Regular attacks won't work any more - it's time to assassinate the rogue!";
		}

		int cost = lowcost + random(highcost - lowcost);
		//TODO: Deduct channel currency for attacks

		if (random(success + fail) < fail) return sprintf("$$ %s but misses. $$ uses %d energy.", msg, cost);

		rogue_hp -= power;
		if (name == "assassinate")
			return "@$$: You have assassinated the rogue! Congratulations!";
		return sprintf("$$ %s for %d hp. $$ uses %d energy, and the [fake] rogue has %d hp left.", msg, power, cost, rogue_hp);
	}
}

void create(string|void name)
{
	::create(name);
	//Attacks all have "fake" prefix so they don't conflict with the original
	attack( 20, 4, 1,  8, 16, "fpunch", "lobs a punch at the [fake] rogue");
	attack( 40, 3, 1, 10, 18, "fkick", "kicks the [fake] rogue");
	attack( 60, 2, 1, 14, 20, "ffireball", "casts a fireball at the [fake] rogue");
	attack( 80, 1, 2, 18, 26, "fslash", "slashes the [fake] rogue with his sword");
	attack(100, 1, 8, 20, 28, "fassassinate", "attempts to assassinate the [fake] rogue");
}
