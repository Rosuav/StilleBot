inherit command;
constant hidden_command = 1;
constant active_channels = ({"ladydreamtv"});

mapping special = ([]);

constant responses = ({
	0, //One chance of getting a rare coded response
	"$$: I'm sorry, I'm in devicatLURK mode and can't answer you right now.",
	"$$: Absolutely! No question about it. rosuavLove",
	"$$: Not in a million years, or until GNU Hurd becomes viable, whichever is sooner. devicatBUTT",
	"Oh $$, you flatter me. But I'm afraid I can't answer that. devicatAWW",
	"$$: Yep, you got it! fxnUp",
	"$$: As I see it, yes. maayaHeart",
	"$$: Signs point to yes. devicatMAGIC",
	"$$: Outlook not so good. Don't count on it. devicatPOW",
	"$$: My reply is no. noobsBlondeThump",
	"$$: My source code says yes. rosuavNerd",
	"$$: My sources say no.",
	"$$: Who, me? I think you want to ask CutieCakeBot that. devicatCCB",
	"$$: Honestly, there is no polite way to answer that question. devicatSPOOK",
	"$$: You may want to ask {participant} instead. devicatZZZ",
	"$$: Hmm.... nope, my programming does not cover that. maayaThink",
	"$$: That makes sense to me! devicatLOL",
	"$$: I could tell you, but then I'd have to time you out. rosuavMuted",
	"Oh, I'm fairly sure you already know the answer to this one, $$.",
});

array(function) rare_responses = ({
	lambda(object channel, object person, string param) {
		special[person->user] = lambda(object c, object p, string param2) {
			if (param2 == param) return "$$: Come on, that wasn't *nearly* enough concentration. devicatGRR"; //And keep the special in place
			m_delete(special, person->user);
		};
		return "$$: Concentrate and ask again.";
	},
	lambda(object channel, object person, string param) {
		special[person->user] = lambda(object c, object p, string param2) {
			m_delete(special, person->user);
			if (lower_case(param2) == "hazy") return ({"$$: Correct! You win the love of the crowd. <3 ladydr1HoG", "!give $$ 100"});
		};
		return "$$: Reply hazy, try again.";
	},
	lambda(object channel, object person, string param) {
		special[person->user] = lambda(object c, object p, string param2) {
			m_delete(special, person->user);
			if (has_value(lower_case(param2), "now")) return "$$: Nope, still cannot predict.";
		};
		return "$$: Cannot predict now.";
	},
	lambda(object channel, object person, string param) {
		return "Well, $$, I don't want to say I told you so, but you asked me this in a previous life, and I gave you a perfectly good answer.";
	},
});

echoable_message process(object channel, object person, string param)
{
	if (param == "") return "$$: Ask me a question! Any question! Preferably a yes-no one.";
	//Check if we have a "remembered response"
	function spec = special[person->user];
	if (string resp = spec && spec(channel, person, param)) return resp;
	//Most of the time, pick a standard (generic) response
	if (string resp = random(responses)) return resp;
	//Occasionally, pick a rare and special response
	return random(rare_responses)(channel, person, param);
}
