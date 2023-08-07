/* Graphical command editor

Originally developed outside of StilleBot as https://github.com/Rosuav/CanvasTest - for
early file history, check that repository.

*/
/* TODO
Allow a flag to be removed. Currently, you have to drag a replacement flag, but it should make sense
to say "no I don't want this to be mod-only any more". Or alternatively, always show the default flag??

Pipe dream: Can the label for a text message show emotes graphically?

Note that some legacy forms are not supported and will not be. If you have an old command in such a
form, edit and save it in the default or raw UIs, then open this one.

Some particularly hairy types of operations are not available in tools, but can be imported, and
are then able to be saved into favs. Maybe I'll eventually make a separate tray for them??

An "Element" is anything that can be interacted with. An "Active" is something that can be saved,
and is everything that isn't in the Favs/Trays/Specials.
  - The primary anchor point may belong in Actives or may belong in Specials. Uncertain.
*/
import {set_content, choc, replace_content, lindt, DOM, on, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, DIALOG, DIV, FORM, H3, HEADER, INPUT, LABEL, LI, OPTGROUP, OPTION, P, SECTION, SELECT, TABLE, TD, TEXTAREA, TR, U, UL} = choc; //autoimport

const SNAP_RANGE = 100; //Distance-squared to permit snapping (eg 25 = 5px radius)
const canvas = DOM("#command_gui");
const ctx = canvas.getContext('2d');
const FAV_BUTTON_TEXT = ["Fav ☆", "Fav ★"];
let voices_available = {"": "Channel default"}; //Note that this will show up after the numeric entries, even though it's entered first
Object.keys(voices).forEach(id => voices_available[id] = voices[id].name);
let alertcfg = {stdalerts: [], personals: [], loading: true};
fetch("alertbox?summary", {credentials: "include"}).then(r => r.json()).then(c => alertcfg = c);

document.body.appendChild(DIALOG({id: "properties"}, SECTION([
	HEADER([H3("Properties"), DIV([BUTTON({type: "button", className: "dialog_cancel"}, "x"), BR(), BUTTON({type: "button", id: "toggle_favourite"}, "fav")])]),
	DIV(FORM({id: "setprops", method: "dialog"}, [
		TABLE({id: "params"}), P({id: "typedesc"}), UL({id: "providesdesc"}),
		P({id: "templateinfo"}, [
			"This is a template and cannot be edited directly. Drag it to create something in the", BR(),
			"command, or ==> ", BUTTON({id: "clonetemplate", type: "button"}, "Add to command")
		]),
		P(BUTTON({id: "saveprops", accesskey: "a"}, "Close")), //The access key makes sense when it changes to Apply
	])),
])));
fix_dialogs();

const in_rect = (x, y, rect) => x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
const arrayify = x => Array.isArray(x) ? x : [x];
const ensure_blank = arr => {
	if (arr[arr.length - 1] !== "") arr.push(""); //Ensure the usual empty
	return arr;
};

function automation_to_string(val) {
	if (!val) return "";
	if (!Array.isArray(val)) {
		//Parse string to array, then parse array to string, thus ensuring canonicalization.
		const mode = val.includes(":");
		const m = val.split(mode ? ":" : "-");
		if (m.length === 1) m.push(m[0]);
		val = [m[0]|0, m[1]|0, mode];
	}
	const [m1, m2, mode] = val;
	if (mode) return ("0" + m1).slice(-2) + ":" + ("0" + m2).slice(-2); //hr:min
	else if (m1 >= m2) return ""+m1; //min-min is the same as just min
	else return m1 + "-" + m2; //min-max
}

const default_handlers = {
	//Validation sees the original value and determines whether it's possible for it to be correct.
	validate: val => typeof val === "string" || typeof val === "undefined",
	//Normalization takes the original value and returns a canonical representation of it. The
	//unnormalized version has to have passed validation, but every other part of the code can
	//assume that the data will have been normalized. Note that this should be idempotent, and
	//will be called also on saving.
	//normalize: val => val,
	//Create the appropriate DOM element for this (called a "control" because the word "element"
	//has so many different meanings here).
	make_control: (id, val, el) => INPUT({...id, value: val || "", size: 50}),
	//Fetch the serializable value from the DOM element. Inverse of make_control, to an extent.
	//retrieve_value: (val, el) => val.value,
};
const required = {...default_handlers, validate: val => typeof val === "string"}; //Filter that demands that an attribute be present
const bool_attr = {...default_handlers,
	make_control: (id, val, el) => INPUT({...id, type: "checkbox", checked: val === "on"}),
	retrieve_value: el => el.checked ? "on" : "",
};
const text_message = {...default_handlers,
	validate: val => typeof val === "string" && val !== "",
	make_control: (id, val, el) => {
		//Collect up a list of parents in order from root to here
		//We scan upwards, inserting parents before us, to ensure proper ordering.
		//This keeps the display tidy (having {param} always first, for instance),
		//but also ensures that wonky situations with vars overwriting each other
		//will behave the way the back end would handle them.
		const vars_avail = [];
		for (let par = el; par; par = par.parent && par.parent[0]) {
			vars_avail.unshift(types[par.type].provides || par.provides);
		}
		const allvars = Object.assign({}, ...vars_avail);
		return DIV({className: "msgedit"}, [
			DIV({className: "buttonbox attached"}, Object.entries(allvars).map(([v, d]) => BUTTON({type: "button", title: d, className: "insertvar", "data-insertme": v}, v))),
			TEXTAREA({...id, rows: 10, cols: 60, "data-editme": 1}, el.message || ""),
		]);
	},
	retrieve_value: (el, msg) => {
		//Assumes that we're editing the "message" attribute
		const txt = el.value;
		if (!txt.includes("\n")) return txt;
		//Convert multiple lines into a group of elements of this type
		const lines = txt.split("\n").filter(l => l !== "");
		if (lines.length <= 1) return lines[0] || ""; //Multiple lines but only one non-blank line, so use it as-is.
		msg.message = lines.map((l,i) => ({type: msg.type, message: l, parent: [msg, "message", i]}));
		msg.type = "group";
		actives.push(...msg.message);
		msg.message.push("");
		return msg.message;
	},
};
//Special case: The cooldown name field can contain an internal ID, eg ".fuse:1", which won't be interesting to the user.
const cooldown_name = {...default_handlers,
	normalize: val => {
		if (val && val[0] === '.') return "";
		if (val && val[0] === '*' && val[1] === '.') return "*";
		return val;
	},
	make_control: (id, val, el) => {
		if (!val) val = "";
		const per_user = val[0] === "*";
		if (per_user) val = val.slice(1);
		return [
			INPUT({...id, value: val, size: 50}),
			LABEL([
				INPUT({...id, name: id.name + "-per-user", id: null, type: "checkbox", checked: per_user}),
				"Per user",
			]),
		];
	},
	retrieve_value: (val, el) => (val.nextElementSibling.querySelector("[type=checkbox]").checked ? "*" : "") + val.value,
};
//Special case: Builtins can require custom code.
const builtin_validators = {
	alertbox_id: {...default_handlers,
		make_control: (id, val, el) => SELECT(id, [
			OPTGROUP({label: "Personal alerts"}, [
				alertcfg.personals.map(a => OPTION({".selected": a.id === val, value: a.id}, a.label)),
				!alertcfg.personals.length && OPTION({disabled: true}, alertcfg.loading ? "loading..." : "None"),
			]),
			OPTGROUP({label: "Standard alerts"}, [
				alertcfg.stdalerts.map(a => OPTION({".selected": a.id === val, value: a.id}, a.label)),
				!alertcfg.stdalerts.length && OPTION({disabled: true}, alertcfg.loading ? "loading..." : "None???"), //Should never get "None" here once it's loaded
			]),
		]),
		//NOTE: Will permit anything while loading, but that should only happen if we get a hash link
		//directly to open a command, or if the internet connection is very slow. Either way, the
		//drop-down should be correctly populated by the time someone actually clicks on something.
		validate: val => alertcfg.loading || alertcfg.stdalerts.find(a => a.id === val) || alertcfg.personals.find(a => a.id === val),
	},
	monitor_id: {...default_handlers,
		make_control: (id, val, el) => SELECT(id, [
			//TODO: Sort these in some useful way (or at least consistent)
			Object.entries(monitors).map(([id, m]) => {
				let label = m.text;
				switch (m.type) {
					case "goalbar": label = "Goal bar - " + /:(.*)$/.exec(m.text)[1]; break;
					case "countdown": label = "Countdown - " + /:(.*)$/.exec(m.text)[1]; break;
					default: break; //Simple text can be displayed as-is
				}
				return OPTION({".selected": id === val, value: id}, label);
			}),
		]),
		//NOTE: Will permit anything while loading, but that should only happen if we get a hash link
		//directly to open a command, or if the internet connection is very slow. Either way, the
		//drop-down should be correctly populated by the time someone actually clicks on something.
		validate: val => monitors[val],
	},
};

const builtin_label_funcs = {
	chan_pointsrewards: el => {
		if (!el.builtin_param || typeof el.builtin_param === "string") return "Points rewards"; //TODO: Reformat into new style?
		switch (el.builtin_param[1]) {
			case "enable": if (el.builtin_param[2] !== "0") return "Points reward: enable";
			case "disable": return "Points reward: disable";
			case "title": return "Points reward: Set title";
			case "desc": return "Points reward: Set description";
			case "fulfil": return "Points: Done " + el.builtin_param[2];
			case "cancel": return "Points: Refund " + el.builtin_param[2];
		}
		return "Points rewards";
	},
};
function builtin_types() {
	const ret = { };
	Object.entries(builtins).forEach(([name, blt]) => {
		const b = ret["builtin_" + name] = {
			color: "#ee77ee", children: ["message"], label: builtin_label_funcs[name] || (el => blt.name),
			params: [{attr: "builtin", values: name}],
			typedesc: blt.desc, provides: { },
		};
		const add_param = (param, idx) => {
			if (param[0] === "/") {
				let split = param.split("/"); split.shift(); //Remove the empty at the start
				const label = split.shift();
				const selections = { };
				if (split[0].includes("=")) split = split.map(s => {
					//sscanf(s, "%s=%s", string value, string label);
					const [value, ...rest] = s.split("=");
					selections[value] = rest.join("=");
					return value;
				});
				if (split.length === 1) {
					//Special-case some to allow custom client-side code
					split = builtin_validators[split[0]] || split;
				}
				b.params.push({attr: "builtin_param" + (idx||""), label, values: split, selections});
			}
			else if (param !== "") b.params.push({attr: "builtin_param" + (idx||""), label: param});
		};
		if (typeof blt.param === "string") add_param(blt.param, "");
		else blt.param.forEach(add_param);
		for (let prov in blt) if (prov[0] === '{' && !blt[prov].includes("(deprecated)")) b.provides[prov] = blt[prov];
	});
	return ret;
}

//If we have pointsrewards, remap it into something more useful (as the command anchor gets loaded)
//Note that the rewards mapping is allowed to have loose entries in it, as long as reward_ids is
//accurate and contains no junk.
const rewards = {"": ""}, reward_ids = [""];
let hack_retain_reward_id = null;

const types = {
	anchor_command: {
		color: "#ffff00", fixed: true, children: ["message"],
		label: el => {
			const invok = [];
			const cmdname = DOM("#cmdname").value;
			if (el.access !== "none") {
				const aliases = (el.aliases||"").split(" ").filter(a => a);
				switch (aliases.length) {
					case 0: invok.push(`When ${cmdname} is typed`); break;
					case 1: invok.push(`When ${cmdname} or !${aliases[0]} is typed`); break;
					default: {
						let msg = "When " + cmdname;
						aliases.forEach(a => msg += ", !" + a);
						invok.push(msg + " is typed");
					}
				}
			}
			const auto = automation_to_string(el.automate);
			if (auto) {
				if (auto.includes(':')) invok.push(`At ${auto}`);
				else invok.push(`Every ${auto} minutes`);
			}
			reward_ids.length = 1; //Truncate without rebinding (since the param details uses the same array and mapping)
			try {pointsrewards.forEach(r => {rewards[r.id] = r.title; reward_ids.push(r.id);});} catch (e) { }
			if (el.redemption) {
				if (rewards[el.redemption]) invok.push(`When '${rewards[el.redemption]}' is redeemed`);
				else {
					//If you have this currently connected to a reward, retain that
					//until such time as the *server* rejects it.
					invok.push("When the chosen reward is redeemed");
					hack_retain_reward_id = el.redemption;
				}
			}
			if (hack_retain_reward_id) {
				//If you load up /pointsrewards with a fragment link specifying a reward command,
				//due to peculiarities of timing and what gets loaded when, the list of rewards
				//won't be available for the drop-down. (Closing and reopening the command editor
				//dialog fixes this.) To ensure that data is not lost, hack in the specific ID of
				//the selected reward as the only one that can be selected.
				if (!rewards[hack_retain_reward_id]) rewards[hack_retain_reward_id] = "selected reward";
				if (!reward_ids.includes(hack_retain_reward_id)) reward_ids.push(hack_retain_reward_id);
				//Residual minor flaw: If you load up the page as described, and then delete the
				//reward that invoked the command that got preloaded, it will be retained on the
				//client, and until you save, will look like there's a spurious reward.
			}
			if (reward_ids.length === 1) reward_ids.length = 0; //If there are no rewards whatsoever, show the dropdown differently

			switch (invok.length) {
				case 0: return "Command name: " + cmdname; //Fallback for inactive commands
				case 1: return invok[0] + "..."; //Common case - a single invocation
				default: return invok.map((msg, i) =>
						!i ? msg :
						(i === invok.length - 1 ? "or " : "")
						+ msg[0].toLowerCase() + msg.slice(1)
					).join(", ") + "...";
			}
		},
		typedesc: ["This is how everything starts. Drag flags onto this to apply them. "
			+ "Restricting access affects who may", BR(), "type the command, but it may still "
			+ "be invoked in other ways even if nobody has access."],
		params: [
			{attr: "aliases", label: "Aliases", values: {...default_handlers,
				normalize: val => (val||"").replace(/!/g, ""),
			}},
			{attr: "access", label: "Access", values: ["", "vip", "mod", "none"],
				selections: {"": "Everyone", vip: "VIPs/mods", mod: "Mods only", none: "Nobody"}},
			{label: "Access controls apply only to chat commands; other invocations are separate."},
			{attr: "visibility", label: "Visibility", values: ["", "hidden"],
				selections: {"": "Visible", hidden: "Hidden"}},
			{label: "Hidden commands do not show up to non-mods."},
			{attr: "automate", label: "Automate", values: {...default_handlers,
				normalize: automation_to_string,
			}},
			{label: [ //TODO: Should I support non-text labels like this?
				"To have this command performed automatically every X minutes, put X here (or X-Y to randomize).",
				BR(), "To have it performed automatically at hh:mm, put hh:mm here.",
			]},
			{attr: "redemption", label: "Redemption", values: reward_ids,
				selections: rewards},
			{label: "Invoke this command whenever some channel points reward is redeemed."},
		],
		provides: {
			"{param}": "Anything typed after the command name",
			"{username}": "Name of the user who entered the command",
			"{uid}": "Twitch ID of the user who entered the command",
			"{@mod}": "1 if the command was triggered by a mod/broadcaster, 0 if not",
			"{rewardid}": "UUID of the channel point reward that triggered this, or blank",
			"{redemptionid}": "UUID of the precise channel point redemption (for confirm/cancel)",
			"{msgid}": "ID of the message that caused this command (suitable for replies)",
		},
		width: 400,
		actionlbl: "Edit",
	},
	anchor_trigger: {
		color: "#ffff00", fixed: true, children: ["message"],
		label: el => el.expr2 === "{rewardid}" ? 
				el.expr1 === "-" && el.conditional === "contains" ? "Custom point redemption: any"
				: "Custom point redemption: " + el.expr1
			: el.conditional === "contains" ? `When '${el.expr1}' is typed...` : `When a msg matches ${el.expr1} ...`,
		params: [{attr: "conditional", label: "Match type", values: ["contains", "regexp", "number"],
				selections: {contains: "Simple match", regexp: "Regular expression", number: "Expression evaluation"}},
			{attr: "casefold", label: "Case insensitive", values: bool_attr},
			{attr: "id", label: null}, //Retain the ID but don't show it for editing
			{attr: "expr1", label: "Search for"},
			{attr: "expr2", label: "Trigger type", values: ["%s", "{rewardid}"],
				selections: {"%s": "Regular", "{rewardid}": "Channel point redemption"}},
		],
		provides: {
			"{param}": "The entire message",
			"{username}": "Name of the user who entered the triggering message",
			"{uid}": "Twitch ID of the user who entered the triggering message",
			"{@mod}": "1 if trigger came from a mod/broadcaster, 0 if not",
			"{msgid}": "ID of the message that caused this command (suitable for replies)",
		},
		width: 400,
		actionlbl: "Edit",
	},
	anchor_special: {
		//Specials are... special. The details here will vary based on which special we're editing.
		color: "#ffff00", fixed: true, children: ["message"],
		label: el => "When " + el.shortdesc[0].toLowerCase() + el.shortdesc.slice(1),
		width: 400,
		actionlbl: "Edit",
	},
	trashcan: {
		color: "#999999", fixed: true, children: ["message"],
		label: el => "Drop trash here to discard",
		typedesc: "Anything dropped here can be retrieved until you next reload, otherwise it's gone forever.",
		actionlbl: "🗑", action: self => {self.message = [""]; repaint();},
		actionactive: self => self.message.length > 1,
	},
	//Types can apply zero or more attributes to a message, each one with a set of valid values.
	//Validity can be defined by an array of strings (take your pick), a single string (fixed value,
	//cannot change), undefined (allow user to type), or an array of three numbers [min, max, step],
	//which define a range of numeric values.
	//If the value is editable (ie not a fixed string), also provide a label for editing.
	//These will be detected in the order they are iterated over.
	delay: {
		color: "#77ee77", children: ["message"], label: el => `Delay ${el.delay} seconds`,
		params: [{attr: "delay", label: "Delay (seconds)", values: [1, 86400, 1]}],
		typedesc: "Delay message(s) by a certain length of time",
	},
	voice: {
		color: "#bbbb33", children: ["message"], label: el => "Voice: " + (voices_available[el.voice] || el.voice),
		params: [{attr: "voice", label: "Voice", values: Object.keys(voices_available), selections: voices_available}],
		typedesc: ["Select a different ", A({href: "voices"}, "voice"), " for messages - only available if alternate voices are authorized"],
	},
	whisper_back: {
		color: "#99ffff", width: 400, label: el => "🤫 " + el.message,
		params: [{attr: "dest", values: "/w"}, {attr: "target", values: "$$"}, {attr: "message", label: "Text", values: text_message}],
		typedesc: "Whisper to the person who ran the command",
	},
	whisper_other: {
		color: "#99ffff", children: ["message"], label: el => "🤫 to " + el.target,
		params: [{attr: "dest", values: "/w"}, {attr: "target", label: "Person to whisper to"}],
		typedesc: "Whisper to a specific person",
	},
	reply_back: {
		color: "#aaeeff", width: 400, label: el => "🧵 " + el.message,
		params: [{attr: "dest", values: "/reply"}, {attr: "target", values: "{msgid}"}, {attr: "message", label: "Text", values: text_message}],
		typedesc: "Reply to the command/message that triggered this (if applicable)",
	},
	reply_other: {
		color: "#aaeeff", children: ["message"], label: el => "🧵 to " + el.target,
		params: [{attr: "dest", values: "/reply"}, {attr: "target", label: "Message ID (UUID)"}],
		typedesc: "Reply to a specific message (by its ID)",
	},
	web_message: {
		color: "#99ffff", children: ["message"], label: el => "🌏 to " + el.target,
		params: [{attr: "dest", values: "/web"}, {attr: "target", label: "Recipient"}, {attr: "destcfg", label: "Response to 'Got it' button"}],
		typedesc: ["Leave a ", A({href: "messages"}, "private message"), " for someone"],
	},
	chain_of_command: {
		color: "#66ee66", label: el => "Chain to " + (el.target ? (el.target.startsWith("!") ? "" : "!") + el.target : "command"),
		params: [
			{attr: "dest", values: "/chain"},
			{attr: "target", label: "Command name"}, //TODO: Make this a drop-down
			{attr: "destcfg", label: "Parameters"},
		],
		typedesc: ["Chain to another command (like calling a function)"],
	},
	incr_variable: {
		color: "#dd7777", label: el => `Add ${el.message} to $${el.target}$`,
		params: [{attr: "dest", values: "/set"}, {attr: "destcfg", values: "add"},
			{attr: "target", label: "Variable name"}, {attr: "message", label: "Increment by"}],
		typedesc: ["Update a variable. Can be accessed as $varname$ in this or any other command.", BR(),
			"Use ", CODE("*varname"), " for a per-user variable, and/or ", CODE("varname?"), " for ephemeral."],
	},
	incr_variable_complex: {
		color: "#dd7777", children: ["message"], label: el => `Add onto $${el.target}$`,
		params: [{attr: "dest", values: "/set"}, {attr: "destcfg", values: "add"},
			{attr: "target", label: "Variable name"},],
		typedesc: ["Capture message as a variable update. Can be accessed as $varname$ in this or any other command.", BR(),
			"Use ", CODE("*varname"), " for a per-user variable, and/or ", CODE("varname?"), " for ephemeral."],
	},
	set_variable: {
		color: "#dd7777", label: el => el.message ? `Set $${el.target}$ to ${el.message}` : `Empty out $${el.target}$`,
		params: [{attr: "dest", values: "/set"}, {attr: "target", label: "Variable name"}, {attr: "message", label: "New value"}],
		typedesc: ["Change a variable. Can be accessed as $varname$ in this or any other command.", BR(),
			"Use ", CODE("*varname"), " for a per-user variable, and/or ", CODE("varname?"), " for ephemeral."],
	},
	set_variable_complex: {
		color: "#dd7777", children: ["message"], label: el => `Change variable $${el.target}$`,
		params: [{attr: "dest", values: "/set"}, {attr: "target", label: "Variable name"},],
		typedesc: ["Capture message into a variable. Can be accessed as $varname$ in this or any other command.", BR(),
			"Use ", CODE("*varname"), " for a per-user variable, and/or ", CODE("varname?"), " for ephemeral."],
	},
	foreach: {
		color: "#66ee66", children: ["message"], label: el => +el.participant_activity ? "For each active chatter" : "For each person in chat",
		params: [{attr: "mode", values: "foreach"},
			{attr: "participant_activity", label: "Active in the past X seconds", values: [0, 86400, 1]},],
		typedesc: ["Do something for every person in chat (active time of 0) or everyone who has been", BR(),
			"active recently (eg 300 = five minutes). This user's variables will be available with the", BR(),
			"name ", CODE("each*"), " for any variable."],
	},
	...builtin_types(),
	handle_errors: {
		color: "#ff8800", label: el => "Handle errors",
		params: [{attr: "conditional", values: "string"}, {attr: "expr1", values: "{error}"},
			{attr: "otherwise", values: "Unexpected error: {error}"}],
		typedesc: "Handle potential errors from a builtin",
	},
	conditional_string: {
		color: "#7777ee", children: ["message", "otherwise"], label: el => [
			el.conditional === "string" ? (el.expr1 && el.expr2 ? "If " + el.expr1 + " == " + el.expr2 : el.expr1 ? "If " + el.expr1 + " is blank" : "String comparison")
				: el.conditional === "contains" ? "String includes"
				: el.conditional === "regexp" ? "Regular expression"
				: "?? unknown condition ??",
			"Otherwise:",
		],
		params: [
			{attr: "conditional", label: "Condition type", values: ["string", "contains", "regexp"], selections: {string: "String equals", contains: "String includes", regexp: "Regular expression"}},
			{attr: "casefold", label: "Case insensitive", values: bool_attr},
			{attr: "expr1", label: "Expression 1"}, {attr: "expr2", label: "Expression 2"},
		],
		typedesc: "Make a decision - if THIS is THAT, do one thing, otherwise do something else.",
	},
	conditional_number: {
		color: "#7777ee", children: ["message", "otherwise"], label: el => ["Numeric computation", "If it's zero/false:"],
		params: [{attr: "conditional", values: "number"}, {attr: "expr1", label: "Expression"}],
		typedesc: "Make a decision - if the result's nonzero, do one thing, otherwise do something else.",
	},
	conditional_spend: {
		color: "#7777ee", children: ["message", "otherwise"], label: el => ["Spend " + el.expr2 + " " + el.expr1, "If it's zero/false:"],
		params: [{attr: "conditional", values: "spend"},
			{attr: "expr1", label: "Variable to spend from"},
			{attr: "expr2", label: "Amount to spend"},
		],
		typedesc: "Spend some of a bot-managed value. Subtracts from the variable but won't let it go below zero.",
	},
	cooldown: {
		color: "#aacc55", children: ["message", "otherwise"], label: el => [el.cdlength + "-second cooldown", "If on cooldown:"],
		params: [{attr: "conditional", values: "cooldown"},
			{attr: "cdlength", label: "Delay (seconds)", values: [1, 86400, 1]}, //TODO: Support hh:mm:ss and show it that way for display
			{attr: "cdname", label: "Tag (optional)", values: cooldown_name}],
		typedesc: ["Prevent the command from being used too quickly. If it's been used recently, the second block happens instead.",
			BR(), "To have several commands share a cooldown, put the same tag in each one (any word or phrase will do)."],
	},
	randrot: {
		color: "#ee7777", children: ["message"], label: el => el.mode === "rotate" ? "Rotate" : "Randomize",
		params: [{attr: "mode", label: "Mode", values: ["random", "rotate"], selections: {random: "Random", rotate: "Rotate"}},
			{attr: "rotatename", label: "Tag (optional)", values: cooldown_name}], //Reuses the cooldown_name handler to hide any autogenerated ones and per-user status
		typedesc: "Each time this is triggered, pick one child and show it. "
			+ "Rotation can specify a synchronization tag so multiple commands can rotate together.",
	},
	text: {
		color: "#77eeee", width: 400, label: el => el.message,
		params: [{attr: "message", label: "Text", values: text_message}],
		typedesc: "Send a message in the channel. Commands like /announce, /me, /ban, etc all work as normal.",
	},
	group: {
		color: "#66dddd", children: ["message"], label: el => "Group",
		typedesc: "Group some elements for convenience. Has no inherent effect.",
	},
	flag: {
		color: "#aaddff", label: el => el.icon,
		style: "flag", width: 25,
		actionlbl: null,
	},
	dragflag: {
		color: "#aaddff", label: el => el.icon + " " + el.desc,
		style: "flag", width: 150,
		actionlbl: null,
	},
};

//Encapsulation breach: If there's a #cmdname, it's going to affect the command_anchor.
on("change", "#cmdname", e => repaint());

const path_cache = { };
function element_path(element) {
	if (element === "") return {totheight: 30}; //Simplify height calculation
	//Calculate a cache key for the element. This should be affected by anything that affects
	//the path/clickable area, but not things that merely affect display (colour, text, etc).
	let cache_key = element.type;
	for (let attr of types[element.type].children || []) {
		const childset = element[attr] || [""];
		cache_key += "[" + childset.map(c => element_path(c).totheight).join() + "]";
	}
	if (path_cache[cache_key]) return path_cache[cache_key];
	const type = types[element.type];
	const path = new Path2D;
	const width = type.width || 200;
	path.moveTo(0, 0);
	if (type.style === "flag") {
		path.lineTo(width, 0);
		path.bezierCurveTo(width + 4, 12, width - 4, 5, width, 20); //Curve on the edge of the flag
		path.lineTo(5, 20);
		path.lineTo(5, 35);
		path.lineTo(0, 35);
		path.closePath();
		return path_cache[cache_key] = {path, connections: [], totheight: 30, labelpos: [14]};
	}
	path.lineTo(width, 0);
	path.lineTo(width, 30);
	let y = 30;
	const connections = [], labelpos = [20];
	if (type.children) for (let i = 0; i < type.children.length; ++i) {
		if (i) {
			//For second and subsequent children, add a separator bar and room for a label.
			path.lineTo(width, y);
			path.lineTo(width, y += 20);
			labelpos.push(y - 5);
		}
		const childset = element[type.children[i]];
		if (childset) for (let c = 0; c < childset.length; ++c) {
			connections.push({x: 10, y, name: type.children[i], index: c});
			path.lineTo(10, y);
			path.lineTo(10, y + 5);
			path.arc(10, y + 15, 10, Math.PI * 3 / 2, Math.PI / 2, false);
			path.lineTo(10, y += element_path(childset[c]).totheight);
		}
		path.lineTo(10, y += 10); //Leave a bit of a gap under the last child slot to indicate room for more
	}
	path.lineTo(0, y);
	path.lineTo(0, 30);
	if (!type.fixed) { //Object has a connection point on its left edge
		path.lineTo(0, 25);
		path.arc(0, 15, 10, Math.PI / 2, Math.PI * 3 / 2, true);
	}
	path.closePath();
	return path_cache[cache_key] = {path, connections, totheight: y, labelpos};
}
const actives = [
	//Generic anchor controlled by the caller
	{type: "anchor_trigger", x: 10, y: 45, message: [""]}, //Stick with Trigger and you'll live (unless the basis object changes the type)
];
const favourites = [];
const trays = { };
const tray_tabs = [
	{name: "Default", color: "#efdbb2", items: [
		{type: "text", message: "Simple text message"},
		{type: "randrot", mode: "random"},
		{type: "conditional_string", conditional: "string", expr1: "{param}"},
		{type: "voice", voice: ""},
		{type: "builtin_calc", builtin_param: "1 + 2 + 3",
			message: [{type: "text", message: "That works out to: {result}"}]},
	]},
	{name: "Alternate delivery", color: "#f7bbf7", items: [
		{type: "whisper_back", message: "Shh! This is a whisper!"},
		{type: "whisper_other", target: "{param}", message: [{type: "text", message: "Here's a whisper!"}]},
		{type: "reply_back", message: "Join the thread!"},
		{type: "web_message", target: "{param}", message: [
			{type: "text", message: "This is a top secret message."},
		]},
		{type: "set_variable", target: "deaths", message: "0"},
		{type: "incr_variable", target: "deaths", message: "1"},
		{type: "delay", delay: "2"},
	]},
	{name: "Control Flow", color: "#bbbbf7", items: [
		{type: "conditional_spend", expr1: "*points", expr2: "5"},
		{type: "conditional_number", expr1: "$deaths$ > 10"},
		{type: "conditional_string", conditional: "regexp", expr1: "[Hh]ello", expr2: "{param}"},
		{type: "chain_of_command", target: "", destcfg: ""},
		//NOTE: Even though they're internally conditionals too, cooldowns don't belong in this tray.
		//Conversely, even though argsplit isn't really control flow, it fits into the same kind of
		//use case, where you're thinking more like a programmer.
	]},
	{name: "Interaction", color: "#ffffbb", items: [
		{type: "builtin_shoutout", builtin_param: "%s"},
		{type: "builtin_chan_labels"},
		{type: "builtin_uservars"},
		{type: "builtin_tz", builtin_param: "Los Angeles"},
	]},
	{name: "Advanced", color: "#bbffbb", items: [
		{type: "builtin_chan_pointsrewards", message: [{type: "handle_errors"}]},
		{type: "randrot", mode: "rotate"},
		{type: "builtin_argsplit", builtin_param: "{param}"},
		{type: "cooldown", cdlength: "30", cdname: ""},
	]},
	{name: "Extras", color: "#7f7f7f", items: [ //I'm REALLY not happy with these names.
		{type: "handle_errors"},
		{type: "builtin_chan_monitors"},
		{type: "builtin_chan_giveaway"},
		{type: "builtin_hypetrain"},
		{type: "foreach", "participant_activity": "300"},
	]},
];
const seen_types = {trashcan: 1};
function make_template(el, par) {
	if (el === "") return;
	//Remove this element from actives if present. Note that this is quite inefficient
	//on recursive templates, but I don't really care.
	const idx = actives.indexOf(el);
	if (idx !== -1) actives.splice(idx, 1);
	el.template = true;
	if (par) el.parent = par;
	seen_types[el.type] = 1;
	for (let attr of types[el.type].children || []) {
		if (!el[attr]) el[attr] = [""];
		else ensure_blank(el[attr]).forEach((e, i) => make_template(e, [el, attr, i]));
	}
}
const _hotkeys = "qwertyuop"; //Skip i b/c "insert"
tray_tabs.forEach((t, i) => {
	t.hotkey = i + 1;
	(trays[t.name] = t.items).forEach((e, k) => {make_template(e); e.hotkey = _hotkeys[k];});
});
//Search for any type that can't be created from a template
for (let t in types) if (!seen_types[t]) {
	if (t.startsWith("anchor_") || t.endsWith("flag")) continue;
	if (t.startsWith("builtin_")) {
		//For a quick look at all missing builtins, add them to the last tray:
		//const el = {type: t, hotkey: _hotkeys[trays.Extras.length]};
		//make_template(el);
		//trays.Extras.push(el);
	}
	//else console.log("UNSEEN TYPE", t); //Audit to ensure that we have all the ones that matter
}
let current_tray = "Default";
const trashcan = {type: "trashcan", message: [""]};
const specials = [trashcan];
let facts = []; //FAvourites, Current Tray, and Specials. All the elements in the templates column.
function refactor() {facts = [].concat(favourites, trays[current_tray], specials);}
const tab_width = 15, tab_height = 70;
const tray_x = canvas.width - tab_width - 5; let tray_y; //tray_y is calculated during repaint
const template_x = tray_x - 210, template_y = 10;
const paintbox_x = 250, paintbox_height = 40;
const paintbox_width = 250; //Should this be based on the amount of stuff in it?
let traytab_path = null, paintbox_path = null;
let dragging = null, dragbasex = 50, dragbasey = 10;

//Each flag set, identified by its attribute name, offers a number of options.
//Each option has an emoji icon, optionally a colour, and a long desc used when dragging.
//There must always be an empty-string option, which is also used if the attribute isn't set.
const flags = {
	access: {
		"none": {icon: "🔒", desc: "Access: None"},
		"mod": {icon: "🗡️", color: "#44bb44", desc: "Access: Mods"},
		"vip": {icon: "💎", color: "#ff88ff", desc: "Access: Mods/VIPs"},
		"": {icon: "👪", desc: "Access: Everyone"},
	},
	visibility: {
		"": {icon: "🌞", desc: "Public command"},
		"hidden": {icon: "🌚", desc: "Secret command"},
	},
};
function make_flag_flags() {
	let x = paintbox_x;
	for (let attr in flags) {
		for (let value in flags[attr]) {
			const f = flags[attr][value];
			f.type = "flag"; f.template = true;
			f.x = x += 30; f.y = 2;
			f.attr = attr; f.value = value;
			specials.push(f);
		}
		x += 20;
	}
}
make_flag_flags(); refactor();

const textlimit_cache = { };
function limit_width(ctx, txt, width) {
	const key = ctx.font + ":" + width + ":" + txt;
	if (textlimit_cache[key]) return textlimit_cache[key];
	//Since we can't actually ask the text renderer for character positions, we have to do it ourselves.
	//First try: See if the entire text fits.
	let metrics = ctx.measureText(txt);
	if (width === "") return textlimit_cache[key] = metrics.width; //Actually we're just doing a cached measurement.
	if (metrics.width <= width) return textlimit_cache[key] = txt; //Perfect, all fits.
	//We have to truncate. Second try: The other extreme - a single ellipsis.
	if (limit_width(ctx, "…", "") > width) return ""; //Wow that is super narrow... there's no hope for you.
	//Okay. So we can fit an ellipsis, but not the whole text. Search for the truncation
	//that fits, but such that even a single additional character wouldn't.
	//Our first guess is the proportion of the string that would fit, if every character
	//had the same width.
	let guess = Math.floor((width / metrics.width) * txt.length);
	let fits = 0, spills = 0; //These will never legitly be zero, since a length of 1 should fit
	//Having made a guess based on an assumption which, while technically invalid, is actually
	//fairly plausible for most text, we then jump four characters at a time to try to find a
	//span that contains the limit. From that point, we binary search (which should take exactly
	//two more steps) to get our final result. Under normal circumstances, the first two guesses
	//will already span the goal, so the total number of probes will be four, plus the full text
	//above; if the text is a bit more skewed, it might be five. This is better than a naive
	//binary search for any text longer than 32 characters, and anything shorter than that will
	//fit anyway. The flip side is that pathological examples like "w"*30 + "i"*1000 will take
	//ridiculously large numbers of probes to try to resolve. I don't think that's solvable.
	while (!fits || !spills || (spills - fits) > 1) {
		const w = limit_width(ctx, txt.slice(0, guess) + "…", "");
		if (w <= width) fits = guess; else spills = guess;
		if (!fits) guess -= guess > 4 ? 4 : 1;
		else if (!spills) guess += guess < txt.length - 4 ? 4 : 1;
		else guess = Math.floor((fits + spills) / 2);
		if (guess === fits || guess === spills) break; //Shouldn't happen, but just in case...
	}
	return textlimit_cache[key] = txt.slice(0, fits) + "…";
}

let max_descent = 0;
let draw_focus_ring = false; //Set to true when keyboard changes focus, false when mouse does
function draw_at(ctx, el, parent, reposition) {
	if (el === "") return;
	if (reposition) {el.x = parent.x + reposition.x; el.y = parent.y + reposition.y;}
	const path = element_path(el);
	max_descent = Math.max(max_descent, (el.y|0) + path.totheight);
	const type = types[el.type];
	ctx.save();
	ctx.translate(el.x|0, el.y|0);
	ctx.fillStyle = el.color || type.color;
	ctx.fill(path.path);
	const fallback = draw_focus_ring && canvas.querySelector('[key="' + el.key + '"]');
	if (fallback) {
		//Unfortunately this will cause a lot of snap scrolling. So we snap right back.
		const scr = canvas.parentElement.scrollTop;
		ctx.drawFocusIfNeeded(path.path, fallback);
		canvas.parentElement.scrollTop = scr;
		//TODO: Check if this path is on screen, and if not, don't snap back.
	}
	ctx.font = "12px sans";
	let right_margin = 4;
	if (type.actionlbl !== null) { //Set to null to force there to be no action link
		let x = (type.width||200) - right_margin, y = path.labelpos[0];
		const lbl = type.actionlbl || "🖉";
		if (!el.actionlink) {
			//Assuming that the font size is constant, the position and size of this
			//box relative to the element won't ever change. If anything changes it,
			//clear out el.actionlink to force it to be recalculated.
			const size = ctx.measureText(lbl);
			//The text will be right-justified, so its origin is shifted left by the width.
			const origin = x - (size.actualBoundingBoxRight - size.actualBoundingBoxLeft);
			el.actionlink = {
				left: origin + size.actualBoundingBoxLeft - 2,
				right: origin + size.actualBoundingBoxRight + 2,
				top: y - size.actualBoundingBoxAscent - 1,
				bottom: y + 2,
			};
		}
		const wid = el.actionlink.right - el.actionlink.left;
		x -= wid - 4;
		const active = type.actionactive ? type.actionactive(el) : true; //Default is always active
		ctx.fillStyle = active ? "#0000FF" : "#000000";
		ctx.fillText(lbl, x, y);
		//Drawing a line is weirdly nonsimple. Let's cheat and draw a tiny rectangle.
		if (active) ctx.fillRect(el.actionlink.left + 2, y + 2, wid - 3, 1);
		right_margin += wid;
	}
	ctx.fillStyle = "black";
	const labels = arrayify(type.label(el));
	let label_x = 20;
	if (type.style === "flag") label_x = 6; //Hack!
	else if (el.template) labels[0] = "⯇ " + labels[0];
	else if (!type.fixed) labels[0] = "⣿ " + labels[0];
	if (draw_focus_ring && el.hotkey) labels[0] = "[" + el.hotkey + "] " + labels[0]; //FIXME: Ugly
	const w = (type.width || 200) - label_x - right_margin;
	for (let i = 0; i < labels.length; ++i) ctx.fillText(limit_width(ctx, labels[i], w), label_x, path.labelpos[i]);
	ctx.stroke(path.path);
	let flag_x = 220;
	for (let attr in flags) {
		const flag = flags[attr][el[attr]];
		if (flag && el[attr] !== "") {
			draw_at(ctx, {...flag, x: flag_x -= 30, y: -24});
		}
	}
	ctx.restore();
	const children = type.children || [];
	let conn = path.connections, cc = 0;
	for (let i = 0; i < children.length; ++i) {
		const childset = el[children[i]];
		for (let c = 0; c < childset.length; ++c) {
			draw_at(ctx, childset[c], el, conn[cc++]);
		}
	}
}

function render(set, y) {
	set.forEach(el => {
		el.x = template_x; el.y = y;
		draw_at(ctx, el);
		y += element_path(el).totheight + 10;
	});
}
//NOTE: The color *must* be a string of the form "#rrggbb" as it will have alpha added
function boxed_set(set, color, desc, y, minheight) {
	const h = Math.max(set.map(el => element_path(el).totheight + 10).reduce((x,y) => x + y, 30), minheight || 0);
	ctx.save();
	ctx.fillStyle = color;
	ctx.fillRect(template_x - 10, y, 220, h);
	ctx.strokeRect(template_x - 10, y, 220, h);
	ctx.font = "12px sans"; ctx.fillStyle = "black";
	ctx.fillText(desc, template_x + 15, y + 19, 175);
	ctx.beginPath();
	ctx.rect(template_x - 9, y, 218, h);
	ctx.clip();
	render(set, y + 30);
	//Fade wide elements out by overlaying them with the background colour in ever-increasing alpha
	const fade_right = ctx.createLinearGradient(template_x + 200, 0, template_x + 210, 0);
	fade_right.addColorStop(0, color + "00");
	fade_right.addColorStop(1, color);
	ctx.fillStyle = fade_right;
	ctx.fillRect(template_x + 200, y, 10, h);
	ctx.restore();
	return y + h + 10;
}

let next_key_idx = 1;
function repaint() {
	ctx.clearRect(0, 0, canvas.width, canvas.height);
	max_descent = 600; //Base height, will never shrink shorter than this
	tray_y = boxed_set(favourites, "#eeffee", "> Drop here to save favourites <", template_y);
	//Draw the tabs down the side of the tray
	let tab_y = tray_y + tab_width, curtab = null;
	if (!traytab_path) {
		traytab_path = new Path2D;
		traytab_path.moveTo(0, 0);
		traytab_path.lineTo(tab_width, tab_width);
		traytab_path.lineTo(tab_width, tab_height - tab_width / 2);
		traytab_path.lineTo(0, tab_height + tab_width / 2);
	}
	for (let tab of tray_tabs) {
		tab.y = tab_y;
		if (tab.name === current_tray) curtab = tab; //Current tab is drawn last in case of overlap
		else {
			ctx.save();
			ctx.translate(tray_x, tab_y);
			ctx.fillStyle = tab.color;
			ctx.fill(traytab_path);
			ctx.stroke(traytab_path);
			ctx.font = "12px sans"; ctx.fillStyle = "black";
			ctx.fillText(tab.hotkey, 3, 43);
			ctx.restore();
		}
		tab_y += tab_height;
	}
	tab_y += tab_width * 3 / 2;
	let spec_y = boxed_set(trays[current_tray], curtab ? curtab.color : "#00FF00", "Current tray: " + current_tray, tray_y, tab_y - tray_y);
	if (curtab) {
		//Draw the current tab
		ctx.save();
		ctx.translate(tray_x, curtab.y);
		//Remove the dividing line. It might still be partly there but this makes the tab look connected.
		ctx.strokeStyle = curtab.color;
		ctx.strokeRect(0, 0, 0, tab_height + tab_width / 2);
		ctx.fillStyle = curtab.color; ctx.strokeStyle = "black";
		ctx.fill(traytab_path);
		ctx.stroke(traytab_path);
		ctx.font = "12px sans"; ctx.fillStyle = "black";
		ctx.fillText(curtab.hotkey, 3, 43);
		ctx.restore();
	}
	trashcan.x = template_x; trashcan.y = spec_y + 25;

	if (!paintbox_path) {
		paintbox_path = new Path2D;
		paintbox_path.moveTo(0, 0);
		paintbox_path.lineTo(tab_width, paintbox_height);
		paintbox_path.lineTo(paintbox_width - tab_width, paintbox_height);
		paintbox_path.lineTo(paintbox_width, 0);
	}
	ctx.save();
	ctx.translate(paintbox_x, 0);
	ctx.fillStyle = "#efdbb2";
	ctx.fill(paintbox_path);
	ctx.stroke(paintbox_path);
	ctx.restore();
	specials.forEach(el => draw_at(ctx, el));

	const focus = document.activeElement.getAttribute("key");
	if (next_key_idx > 0) replace_content(canvas, actives.map((el, idx) => {
		if (!el.key) el.key = next_key_idx++;
		return lindt.DIV({key: el.key, tabindex: idx}, types[el.type].label(el));
	}));
	const focusel = focus && canvas.querySelector('[key="' + focus + '"]');
	if (focusel) focusel.focus({preventScroll: true});
	actives.forEach(el => el.parent || el === dragging || draw_at(ctx, el));
	//if (focus) repaint_that_element(); //TODO: Repaint the element with focus, or at least its focus ring
	if (dragging) draw_at(ctx, dragging); //Anything being dragged gets drawn last, ensuring it is at the top of z-order.
	if (max_descent != canvas.height) {canvas.height = max_descent; repaint();}
}
repaint();

function save_favourites() {ws_sync.send({cmd: "prefs_update", cmd_favourites: favourites.map(element_to_message)})}
function load_favourites(favs) {
	if (!Array.isArray(favs)) return;
	const newfavs = favs.map(f => message_to_element(f, el => el));
	favourites.splice(0); //Replace all favs with the loaded ones.
	for (let f of newfavs) {
		if (!is_favourite(f)) {make_template(f); favourites.push(f);}
	}
	refactor(); repaint();
}
ws_sync.prefs_notify("cmd_favourites", fav => load_favourites(fav));
load_favourites(ws_sync.get_prefs().cmd_favourites); //In case it's already been fetched once we load

function remove_child(childset, idx) {
	while (++idx < childset.length) {
		const cur = childset[idx - 1] = childset[idx];
		if (cur === "") continue;
		//assert cur.parent is array
		//assert cur.parent[0][cur.parent[1]] is childset
		cur.parent[2]--;
	}
	childset.pop(); //assert returns ""
}

//Check if an element contains the given (x,y) position.
//If this or any of its children contains it, return the child which does.
function element_contains(el, x, y) {
	if (el === "") return null; //Empty slots contain nothing.
	if (ctx.isPointInPath(element_path(el).path, x - el.x, y - el.y)) return el;
	for (let attr of types[el.type].children || [])
		for (let child of el[attr] || []) {
			let c = element_contains(child, x, y);
			if (c) return c;
		}
	return null;
}

//TODO maybe: Have some kind of binary space partitioning that makes this less inefficient.
function element_at_position(x, y, filter) {
	for (let el of actives) {
		//Actives check only themselves, because children of actives are themselves actives,
		//and if you grab a child out of an element, it should leave its parent and go and
		//cleave to its mouse cursor.
		if (filter && !filter(el)) continue;
		if (ctx.isPointInPath(element_path(el).path, x - el.x, y - el.y)) return el;
	}
	for (let el of facts) {
		if (filter && !filter(el)) continue;
		//With facts, also descend to children - but if one matches, return the top-level.
		if (element_contains(el, x, y)) return el;
	}
}

function clone_template(t, par) {
	if (t === "") return "";
	const el = {...t};
	delete el.template;
	if (el.type === "flag") el.type = "dragflag"; //Hack - dragging a flag unfurls it (and doesn't add an active element)
	else actives.push(el);
	if (par && el.parent) el.parent[0] = par;
	else delete el.parent;
	delete el.hotkey;
	for (let attr of types[el.type].children || [])
		el[attr] = el[attr].map(e => clone_template(e, el));
	return el;
}

let clicking_on = null; //If non-null, will have rectangle in clicking_on.actionlink
canvas.addEventListener("pointerdown", e => {
	if (e.button) return; //Only left clicks
	e.preventDefault();
	if (e.offsetX >= tray_x) {
		for (let tab of tray_tabs) {
			if (e.offsetY >= tab.y && e.offsetY <= tab.y + tab_height) {
				current_tray = tab.name;
				refactor(); repaint();
			}
		}
		return;
	}
	let el = element_at_position(e.offsetX, e.offsetY, el => el.actionlink);
	if (el && in_rect(e.offsetX - el.x, e.offsetY - el.y, el.actionlink))
		clicking_on = el; //A potential click starts with a mouse down over the link, and never leaves it before mouse up.
	dragging = null;
	el = element_at_position(e.offsetX, e.offsetY, el => !types[el.type].fixed);
	if (!el) return;
	e.target.setPointerCapture(e.pointerId);
	if (el.template || e.ctrlKey) {
		//Clone and spawn. Holding Ctrl allows you to copy any element.
		el = clone_template(el);
		el.fresh = true;
		refactor();
	}
	dragging = el; dragbasex = e.offsetX - el.x; dragbasey = e.offsetY - el.y;
	//Note that the element doesn't lose its parent until you first move the mouse.
});

function has_parent(child, parent) {
	while (child) {
		if (child === parent) return true;
		if (!child.parent) return false;
		child = child.parent[0];
	}
}

function snap_to_elements(xpos, ypos) {
	for (let el of [...actives, ...specials]) { //TODO: Don't make pointless arrays
		if (el.template || has_parent(el, dragging)) continue;
		const path = element_path(el);
		for (let conn of path.connections || []) {
			if (el[conn.name][conn.index] !== "") continue;
			const snapx = el.x + conn.x, snapy = el.y + conn.y;
			if (((snapx - xpos) ** 2 + (snapy - ypos) ** 2) <= SNAP_RANGE)
				return [snapx, snapy, el, conn]; //First match locks it in. No other snapping done.
		}
	}
	return [xpos, ypos, null, null];
}

canvas.addEventListener("pointermove", e => {
	let cursor = "default";
	if (clicking_on && in_rect(e.offsetX - clicking_on.x, e.offsetY - clicking_on.y, clicking_on.actionlink)) {
		//Still clicking on the same link
		canvas.style.cursor = "pointer";
		return;
	}
	clicking_on = null;
	if (dragging) {
		cursor = "grabbing";
		if (dragging.parent) {
			const childset = dragging.parent[0][dragging.parent[1]], idx = dragging.parent[2];
			childset[idx] = "";
			//If this makes a double empty, remove one of them.
			//This may entail moving other elements up a slot, changing their parent pointers.
			//(OOB array indexing will never return an empty string)
			//Note that it is possible to have three in a row, in which case we'll remove twice.
			while (childset[idx - 1] === "" && childset[idx] === "") remove_child(childset, idx);
			if (childset[idx] === "" && childset[idx + 1] === "") remove_child(childset, idx);
			dragging.parent = null;
		}
		[dragging.x, dragging.y] = snap_to_elements(e.offsetX - dragbasex, e.offsetY - dragbasey);
		repaint();
	}
	else {
		let el = element_at_position(e.offsetX, e.offsetY, el => el.actionlink);
		if (el && in_rect(e.offsetX - el.x, e.offsetY - el.y, el.actionlink)) {
			const type = types[el.type];
			if (!type.actionactive || type.actionactive(el))
				cursor = "pointer";
		}
		else {
			el = element_at_position(e.offsetX, e.offsetY, el => !types[el.type].fixed);
			if (el && e.ctrlKey) cursor = "copy";
			//else if (el) cursor = el.template ? "copy" : "default"; //Changing the cursor emphasizes dragging but obscures double-clicking. Probably a bad tradeoff.
		}
	}
	canvas.style.cursor = cursor;
});

function content_only(arr) {return (arr||[]).filter(el => el);} //Filter out any empty strings or null entries
//Check if two templates are functionally equivalent, based on saveable attributes
function same_template(t1, t2) {
	if (t1 === "" && t2 === "") return true;
	if (t1 === "" || t2 === "") return false;
	if (t1.type !== t2.type) return false;
	const type = types[t1.type];
	if (type.params) for (let p of type.params) if (p.attr) {
		let v1 = t1[p.attr], v2 = t2[p.attr];
		if (Array.isArray(v1) && Array.isArray(v2)) {
			//Compare arrays element-wise
			if (v1.length !== v2.length) return false;
			for (let i = 0; i < v1.length; ++i) if (v1[i] !== v2[i]) return false;
		}
		else if (v1 !== v2) return false;
	}
	for (let attr of type.children || []) {
		const c1 = content_only(t1[attr]), c2 = content_only(t2[attr]);
		if (c1.length !== c2.length) return false;
		for (let i = 0; i < c1.length; ++i)
			if (!same_template(c1[i], c2[i])) return false;
	}
	return true;
}
function is_favourite(el) {
	for (let f of favourites) {
		if (same_template(f, el)) return f;
	}
	return null;
}

canvas.addEventListener("pointerup", e => {
	if (clicking_on) {
		const type = types[clicking_on.type];
		if (type.action) type.action(clicking_on);
		else open_element_properties(clicking_on); //Default action: Same as double-click
		clicking_on = null;
	}
	if (!dragging) return;
	if (dragging.key) {
		e.preventDefault();
		draw_focus_ring = false; //Clicking hides the focus ring. (Or should it simply not show it?)
		set_canvas_focus(dragging);
	}
	e.target.releasePointerCapture(e.pointerId);
	//Recalculate connections only on pointer-up. (Or would it be better to do it on pointer-move?)
	if (dragging.type === "dragflag") {
		//Special: Dragging a flag applies it to the anchor, or discards it. Nothing else.
		//TODO: Show this on pointer-move too
		let x = e.offsetX - dragbasex, y = e.offsetY - dragbasey;
		const anchor = actives[0]; //assert anchor.type =~ "anchor*"
		if (x >= anchor.x - 10 && x <= anchor.x + 220 && y >= anchor.y - 30 &&
				y <= anchor.y + element_path(anchor).totheight + 10) {
			anchor[dragging.attr] = dragging.value;
		}
		dragging = null;
		repaint();
		return;
	}
	let parent, conn;
	[dragging.x, dragging.y, parent, conn] = snap_to_elements(e.offsetX - dragbasex, e.offsetY - dragbasey);
	if (dragging.x > template_x - 100) {
		//Dropping something over the favourites (the top section of templates) will save it as a
		//favourite. Dropping it anywhere else (over templates, over trash, or below the trash)
		//will dump it on the trash. It can be retrieved until reload, otherwise it's gone forever.
		if (dragging.y < tray_y) {
			//Three possibilities.
			//1) A favourite was dropped back onto favs (while still fresh)
			//   - Discard it. It's a duplicate.
			//2) A template was dropped onto favs (while still fresh)
			//   - Save as fav, discard the dragged element.
			//3) A non-fresh element was dropped
			//   - Remove the draggable element and add to favs.
			//They all function the same way, though: remove the Active, add to Favourites,
			//but deduplicate against all other Favourites.
			make_template(dragging);
			if (!is_favourite(dragging)) {favourites.push(dragging); save_favourites();}
			refactor();
			dragging = null; repaint();
			return;
		}
		if (dragging.fresh) {
			//It's been picked up off the template but never dropped. Just discard it.
			make_template(dragging); //Easiest way to purge it from actives recursively.
			refactor();
			dragging = null; repaint();
			return;
		}
		for (let c of element_path(trashcan).connections) {
			if (trashcan.message[c.index] === "") {
				parent = trashcan; conn = c;
				break;
			}
		}
	}
	delete dragging.fresh;
	if (parent) {
		const childset = parent[conn.name];
		childset[conn.index] = dragging;
		dragging.parent = [parent, conn.name, conn.index];
		if (conn.index === childset.length - 1) childset.push(""); //Ensure there's always an empty slot at the end
	}
	dragging = null;
	repaint();
});

function currently_focused_element() {
	const focus = document.activeElement;
	if (!focus.closest("canvas")) return null; //Focus not currently on a canvas fallback element
	const key = focus.getAttribute("key");
	for (const el of actives) if (""+el.key === key) return el;
	return null;
}

function set_canvas_focus(el, visible) {
	if (el.key) canvas.querySelector('[key="' + el.key + '"]').focus({preventScroll: true});
	else console.warn("UNABLE TO SET FOCUS - no key set", el); //TODO: Ensure that this never happens
	if (visible) {
		draw_focus_ring = true;
		repaint();
	}
}

canvas.onkeydown = e => {
	if (e.ctrlKey || e.altKey) return; //For now, no ctrl/alt keystrokes
	switch (e.key) {
		case "ArrowUp": case "ArrowDown": {
			//TODO: If Alt held, move currently selected element in the given direction???
			const focus = currently_focused_element();
			if (!focus) break;
			if (!focus.parent && e.key === "ArrowUp") break;
			//Special case: Down from the anchor goes to its first child.
			let [par, parslot, paridx] = focus.parent || [focus, "message", -1];
			const partype = types[par.type];
			e.preventDefault();
			const dir = e.key === "ArrowDown" ? 1 : -1;
			while (1) {
				paridx += dir;
				if (paridx < 0 || paridx >= par[parslot].length) {
					//Find an adjacent available slot, if any
					const slotidx = partype.children.indexOf(parslot) + dir;
					if (slotidx >= 0 && slotidx < partype.children.length) {
						parslot = partype.children[slotidx];
						if (dir < 0) paridx = par[parslot].length - 1;
						else paridx = 0;
					}
					//When moving up, if we run out of children, go to the parent.
					else if (dir < 0) {set_canvas_focus(par, true); return;}
					else if (par.parent) {
						//When moving down, running out of children means asking the
						//parent for its next child.
						[par, parslot, paridx] = par.parent;
						continue;
					}
					else break; //No more children here, and no parents to query. A noble from the Von Habsburg dynasty takes the throne.
				}
				//Can we select this one?
				const child = par[parslot][paridx];
				if (child) {set_canvas_focus(child, true); return;}
			}
			break;
		}
		case "ArrowRight": { //Move to first child
			const focus = currently_focused_element();
			if (!focus) break;
			const type = types[focus.type];
			if (!type.children) break;
			e.preventDefault();
			//Is it worth remembering where we previously were, and returning, rather than
			//always going to the first child?
			//For now, just find the first non-blank child.
			for (let attr of type.children) {
				for (let child of focus[attr]) {
					if (child) {set_canvas_focus(child, true); return;}
				}
			}
			break;
		}
		case "ArrowLeft": { //Move to parent
			const focus = currently_focused_element();
			if (focus && focus.parent) {e.preventDefault(); set_canvas_focus(focus.parent[0], true);}
			break;
		}
		case 'Enter': {
			const focusel = currently_focused_element();
			if (focusel) open_element_properties(focusel);
			e.preventDefault();
			break;
		}
		case 'i': case 'I': {
			//Insert an element at the current position
			const focus = currently_focused_element();
			if (focus && focus.parent) {
				const childset = focus.parent[0][focus.parent[1]];
				const el = {type: "text", message: ""};
				actives.push(el);
				childset.splice(focus.parent[2], 0, el);
				for (let i = focus.parent[2]; i < childset.length; ++i)
					if (childset[i]) childset[i].parent = [focus.parent[0], focus.parent[1], i];
				repaint(); //Force all elements to have their corresponding fallbacks
				set_canvas_focus(el); //Select the new element
				repaint(); //And now paint it with the correct focus ring.
				open_element_properties(el);
			}
			e.preventDefault();
			break;
		}
		case 'q': case 'w': case 'e': case 'r': case 't': case 'y': case 'u': case 'o': case 'p':
		case 'Q': case 'W': case 'E': case 'R': case 'T': case 'Y': case 'U': case 'O': case 'P': {
			e.preventDefault();
			const hotkey = e.key.toLowerCase();
			var appendme = trays[current_tray].find(el => el.hotkey === hotkey);
			if (!appendme) break;
			//Fall through
		}
		case 'a': case 'A': {
			//Append an element to the end of the first child slot of this element, if
			//there is one; otherwise at the end of the child slot of the parent.
			const focus = currently_focused_element();
			if (!focus) break;
			e.preventDefault();
			let parent = focus.parent;
			const childslots = types[focus.type].children;
			if (childslots) {
				//Append to the first child, if there is one; otherwise append a sibling.
				parent = [focus, childslots[e.shiftKey && childslots.length > 1 ? 1 : 0], 0];
			}
			const childset = parent[0][parent[1]];
			//If you press a/A, append a simple text message (initially blank); if you
			//press the hotkey for a tray entry, insert that template here.
			const el = appendme ? clone_template(appendme) : {type: "text", message: ""};
			if (!appendme) actives.push(el);
			//Assume there will always be an empty string at the end, and insert there
			el.parent = [parent[0], parent[1], childset.length - 1];
			childset[childset.length - 1] = el;
			childset.push(""); //And reinstate the trailing empty.
			repaint(); //Force all elements to have their corresponding fallbacks
			set_canvas_focus(el); //Select the new element
			repaint(); //And now paint it with the correct focus ring.
			open_element_properties(el);
			break;
		}
		case '1': case '2': case '3': case '4': case '5': case '6':
		case '7': case '8': case '9': if (e.key <= tray_tabs.length) {
			current_tray = tray_tabs[e.key - 1].name;
			//TODO: Hint to a screenreader that the contents of this tray should be read out
			refactor(); repaint();
			break;
		}
		default: /*console.log("Key!", e);*/ break;
	}
};
document.onkeydown = e => {
	//Pressing Home takes you to the anchor, but only if we don't have a properties dialog open
	if (e.target.closest("dialog") !== canvas.closest("dialog")) return;
	if (e.key === "Home") {
		e.preventDefault();
		canvas.firstElementChild.focus();
		draw_focus_ring = true;
		repaint();
	}
	//Similarly, press ? to toggle the legend.
	if (e.key === "?") {
		e.preventDefault();
		const el = DOM("#command_gui_keybinds input");
		if (el) el.checked = !el.checked;
	}
};

on("mousedown", ".insertvar", e => e.preventDefault()); //Prevent buttons from taking focus when clicked
on("click", ".insertvar", e => {
	const mle = e.match.closest(".msgedit").querySelector("textarea");
	mle.setRangeText(e.match.dataset.insertme, mle.selectionStart, mle.selectionEnd, "end");
});

function update_conditional(el) {
	//If you change the type of conditional expression, re-label the parameters.
	//This is just hacked in because I don't currently have anywhere other than
	//conditionals to use this functionality.
	if (propedit.type.startsWith("anchor_")) return; //Trigger anchors are managed differently.
	const labels = {
		string: {expr1: "Expression 1", expr2: "Expression 2", typedesc: "Make a decision - if THIS is THAT, do one thing, otherwise do something else."},
		contains: {expr1: "Needle", expr2: "Haystack", typedesc: "Make a decision - if Needle in Haystack, do one thing, otherwise do something else."},
		regexp: {expr1: "Reg Exp", expr2: "Compare against", typedesc: ["Make a decision - if ", A({href: "/regexp", target: "_blank"}, "regular expression"), " matches, do one thing, otherwise do something else."]},
	}[el.value];
	if (!labels) return;
	el.form.querySelectorAll("label").forEach(el => {
		if (!el.htmlFor.startsWith("value-")) return;
		const lbl = labels[el.htmlFor.slice(6)];
		if (lbl) set_content(el, lbl + ": ");
	});
	set_content("#typedesc", labels.typedesc);
}
on("change", "select#value-conditional", e => update_conditional(e.match));

let propedit = null;
canvas.addEventListener("dblclick", e => {
	e.stopPropagation();
	const el = element_at_position(e.offsetX, e.offsetY);
	if (el) open_element_properties(el);
});
function open_element_properties(el, type_override) {
	propedit = el;
	const type = types[type_override || el.type];
	set_content("#toggle_favourite", FAV_BUTTON_TEXT[is_favourite(el) ? 1 : 0]).disabled = type.fixed;
	set_content("#typedesc", type.typedesc || el.desc);
	let focus = null;
	set_content("#params", (type.params||[]).map(param => {
		if (param.label === null) return null; //Note that a label of undefined is probably a bug and should be visible.
		if (!param.attr) return TR(TD({colspan: 2}, param.label)); //Descriptive text
		let control, id = {name: "value-" + param.attr, id: "value-" + param.attr, disabled: el.template};
		const values = param.values || default_handlers;
		if (typeof values === "string" && param.attr === "builtin") {
			//For builtins, allow a drop-down to completely change mode.
			//NOTE: This does NOT claim focus; the first "real" attribute
			//should be the one to get focus.
			return TR([TD(LABEL({htmlFor: "value-" + param.attr}, "Builtin type: ")), TD(SELECT({...id, value: values},
				Object.entries(builtins).map(([name, blt]) => OPTION({value: name}, blt.name))))]);
		}
		if (typeof values !== "object") return null; //Fixed strings and such
		let value = el[param.attr];
		const m = /^(builtin_param)([0-9]*)$/.exec(param.attr); //As per the other of this regex, currently restricted to builtin_param
		if (m && Array.isArray(el[m[1]])) value = el[m[1]][m[2] || 0];
		if (values.normalize) value = values.normalize(value);
		if (!values.validate) {
			//If there's no validator function, this is an array, not an object.
			if (values.length === 3 && typeof values[0] === "number") {
				const [min, max, step] = values;
				control = INPUT({...id, type: "number", min, max, step, value});
			} else if (values.length === 0) {
				control = SELECT(id, OPTION({disabled: true}, param.if_empty || "(none)"));
			} else {
				control = SELECT({...id, value}, values.map(v => OPTION({value: v}, (param.selections||{})[v] || v)));
			}
		}
		else control = values.make_control(id, value, el);
		if (!focus) focus = control; //TODO: What if control is an array?
		return TR([TD(LABEL({htmlFor: "value-" + param.attr}, param.label + ": ")), TD(control)]);
	}));
	set_content("#providesdesc", Object.entries(type.provides || el.provides || {}).map(([v, d]) => LI([
		CODE(v), ": " + d,
	])));
	if (!type_override) set_content("#saveprops", "Close"); //On initial open, say that there are no changes. Type override means there are, in effect, changes.
	DOM("#templateinfo").style.display = el.template && el.type !== "flag" ? "block" : "none";
	const sel = DOM("#value-conditional");
	if (sel) update_conditional(sel);
	DOM("#properties").showModal();
	if (focus) (focus.querySelector("[data-editme]") || focus).focus();
}
on("change", "select#value-builtin", e => open_element_properties(propedit, "builtin_" + e.match.value));
//Encapsulation breach: Allow the classic editor to open up an element's properties
//TODO: Refactor some of this into command_editor.js and then have both call on it?
window.open_element_properties = open_element_properties;

on("click", "#toggle_favourite", e => {
	if (types[propedit.type].fixed) return;
	const f = is_favourite(propedit);
	if (f) {
		favourites.splice(favourites.indexOf(f), 1);
		set_content("#toggle_favourite", FAV_BUTTON_TEXT[0]);
	}
	else {
		const t = {...propedit, parent: null}; make_template(t);
		favourites.push(t);
		set_content("#toggle_favourite", FAV_BUTTON_TEXT[1]);
	}
	save_favourites();
	refactor(); repaint();
});

on("click", "#clonetemplate", e => {
	if (!propedit.template || propedit.type === "flag") return;
	const parent = actives[0];
	const path = element_path(parent);
	for (let conn of path.connections || []) {
		if (parent[conn.name][conn.index] !== "") continue;
		const childset = parent[conn.name];
		(childset[conn.index] = clone_template(propedit)).parent = [parent, conn.name, conn.index];
		if (conn.index === childset.length - 1) childset.push(""); //Ensure there's always an empty slot at the end
	}
	propedit = null;
	e.match.closest("dialog").close();
	repaint();
});

on("input", "#properties [name]", e => set_content("#saveprops", [U("A"), "pply changes"]));

on("submit", "#setprops", e => {
	//Hack: This actually changes the type of the element.
	const newtype = document.getElementById("value-builtin");
	if (newtype) propedit.type = "builtin_" + newtype.value;
	const type = types[propedit.type];
	if (!propedit.template && type.params) for (let param of type.params) if (param.attr) {
		const val = param.attr !== "builtin" && document.getElementById("value-" + param.attr);
		if (val) {
			const values = param.values || default_handlers;
			let value = values.retrieve_value ? values.retrieve_value(val, propedit) : val.value;
			//Validate based on the type, to prevent junk data from hanging around until save.
			//Ultimately the server will validate, but it's ugly to let it sit around wrong.
			if (values.normalize) value = values.normalize(value);
			//Special case: builtin_param could be a single string, or could start an array.
			//So if we find builtin_param1, we add it to the array.
			//We expect to hit builtin_param before any others, so that will replace with
			//a string; then builtin_param1 will arrayify, and others will append.
			const m = /^(builtin_param)([0-9]+)$/.exec(param.attr); //Currently restricted to builtin_param, could expand that (but be aware that expr1/expr2 are not done like this)
			if (!m) propedit[param.attr] = value;
			else {
				if (m[2] === "1") propedit[m[1]] = [propedit[m[1]]]; //Arrayify with the value already stored
				propedit[m[1]][m[2]] = value; //TODO: If we've (somehow) skipped over any, fill them with empty strings.
			}
		}
	}
	if (propedit._onsave) propedit._onsave(); //Pseudo-elements from the classic editor need to push data elsewhere
	propedit = null;
	e.match.closest("dialog").close();
	repaint();
});

function element_to_message(el) {
	if (el === "") return "";
	const ret = { };
	const type = types[el.type];
	if (type.children) for (let attr of type.children) {
		ret[attr] = el[attr].filter(e => e !== "").map(element_to_message);
	}
	if (type.params) type.params.forEach(p => p.attr && (ret[p.attr] = typeof p.values === "string" ? p.values : el[p.attr])); //VERIFY: Should be copying unnecessarily but with no consequence
	return ret;
}

function matches(param, msg) {
	//See if the value is compatible with this parameter's definition of values.
	let val = msg[param.attr];
	const m = /^(builtin_param)([0-9]*)$/.exec(param.attr);
	if (m && Array.isArray(msg[m[1]])) val = msg[m[1]][m[2] || 0];
	switch (typeof param.values) {
		case "object": if (param.values.validate) return param.values.validate(val);
		//If there's no validator function, it must be an array.
		if (param.values.length === 3 && typeof param.values[0] === "number") {
			const num = parseFloat(val || 0);
			const [min, max, step] = param.values;
			return num >= min && min <= max && !((num - min) % step);
		} else return param.values.includes(val);
		case "undefined": return typeof val === "string" || typeof val === "undefined";
		case "string": return param.values === val;
		default: return false;
	}
}

function apply_params(el, msg) {
	for (let param of types[el.type].params || []) if (param.attr) {
		//TODO: If builtin_param is an array and the first element has a fixed value, this
		//will break. That's not currently possible with the way things are, but it would
		//be nice to support that, as it'd allow draggables that fix a keyword parameter,
		//and then allow other parameters to be configurable.
		if (typeof param.values !== "string") el[param.attr] = msg[param.attr];
		//else assert msg[param.attr] === param.values
		delete msg[param.attr];
	}
}

function message_to_element(msg, new_elem, array_ok) {
	if (msg === "" || typeof msg === "undefined") return "";
	if (typeof msg === "string") return new_elem({type: "text", message: msg.replace("##CHANNEL##", ws_group.slice(1))});
	if (Array.isArray(msg)) switch (msg.length) {
		case 0: return ""; //Empty array is an empty message
		case 1: return message_to_element(msg[0], new_elem, array_ok);
		default: {
			if (array_ok) return msg.map(el => message_to_element(el, new_elem));
			const group = new_elem({type: "group", message: []}); //Create the group itself before its children, so they're in the convenient order
			msg = msg.map(el => message_to_element(el, new_elem));
			msg.forEach((e, i) => typeof e === "object" && (e.parent = [group, "message", i]));
			group.message = ensure_blank(msg);
			return group;
		}
	}
	if (msg.dest && msg.dest.includes(" ") && !msg.target) {
		//Legacy mode: dest is eg "/set varname" and target is unset
		const words = msg.dest.split(" ");
		msg.dest = words.shift(); msg.target = words.join(" ");
	}
	for (let typename in types) {
		const type = types[typename];
		if (!type.fixed && type.params && type.params.every(p => !p.attr || matches(p, msg))) {
			const el = new_elem({type: typename});
			apply_params(el, msg);
			if (type.children) for (let attr of type.children) {
				if (attr === "message") el[attr] = ensure_blank(arrayify(message_to_element(msg, new_elem, true)));
				else el[attr] = ensure_blank(arrayify(msg[attr]).map(el => message_to_element(el, new_elem)));
				el[attr].forEach((e, i) => typeof e === "object" && (e.parent = [el, attr, i]));
			}
			return el;
		}
	}
	if (msg.message !== undefined) return message_to_element(msg.message, new_elem, array_ok);
	return new_elem({type: "text", message: "Shouldn't happen"});
}

export function gui_load_message(cmd_basis, msg) {
	actives.splice(1); //Truncate
	msg = JSON.parse(JSON.stringify(msg)); //Deep disconnect from the original, allowing mutation
	if (typeof msg === "string" || Array.isArray(msg)) msg = {message: msg};
	//Copy in attributes from the basis object where applicable, or from the message itself
	const typename = cmd_basis.type || actives[0].type;
	actives[0].type = typename;
	const type = types[typename];
	if (type.params) for (let p of type.params) if (p.attr) {
		if (p.attr in cmd_basis) actives[0][p.attr] = cmd_basis[p.attr];
		else if (!flags[p.attr]) { //Flags will be handled below, don't redo the work
			actives[0][p.attr] = msg[p.attr];
			delete msg[p.attr];
		}
	}
	//Copy cmd_basis._shortdesc --> anchor.shortdesc (TODO: Use _shortdesc on both sides?)
	for (let attr in cmd_basis) if (attr[0] === '_') actives[0][attr.slice(1)] = cmd_basis[attr];
	if (msg.action) {
		msg.destcfg = msg.action;
		delete msg.action;
	}
	for (let attr in flags) {
		actives[0][attr] = msg[attr] || "";
		delete msg[attr];
	}
	actives[0].message = ensure_blank(arrayify(message_to_element(msg, el => {actives.push(el); return el;}, true)));
	actives[0].message.forEach((e, i) => typeof e === "object" && (e.parent = [actives[0], "message", i]));
	//Any retained trash is still active. Not radioactive, fortunately; just active.
	trashcan.message.forEach(e => typeof e === "object" && actives.push(e));
	refactor(); repaint();
}

export function gui_save_message() {
	//Starting at the anchor, recursively calculate an echoable message which will create
	//the desired effect.
	const anchor = actives[0]; //assert anchor.type =~ "anchor*"
	const msg = element_to_message(anchor);
	for (let param of types[anchor.type].params || []) if (param.attr)
		msg[param.attr] = typeof param.values === "string" ? param.values : anchor[param.attr];
	for (let attr in flags) {
		const flag = flags[attr][anchor[attr]];
		if (flag && anchor[attr] !== "") msg[attr] = anchor[attr];
	}
	return msg;
}
