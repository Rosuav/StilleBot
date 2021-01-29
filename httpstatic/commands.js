import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, INPUT, DIV, DETAILS, SUMMARY, TABLE, TR, TH, TD, SELECT, OPTION, FIELDSET, LEGEND, CODE} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});
const all_flags = "mode dest access visibility action".split(" ");

on("click", "button.addline", e => {
	let parent = e.match.closest("td").previousElementSibling;
	parent.appendChild(BR());
	parent.appendChild(INPUT({
		name: e.match.dataset.cmd + "!" + e.match.dataset.idx++,
		className: "widetext"
	}));
});

const flags = {
	mode: {"": "Sequential", random: "Random", "*": "Where multiple responses are available, send them all or pick one at random?"},
	dest: {"": "Chat", "/w": "Whisper", "/web": "Private message", "/set": "Set a variable",
		"*": "Where should the response be sent?"},
	action: {"": "Set the value", "add": "Add to the value", "*": "When setting a variable, should it increment or replace?"},
	access: {"": "Anyone", mod: "Mods only", "*": "Who should be able to use this command?"},
	visibility: {"": "Visible", hidden: "Hidden", "*": "Should the command be listed in !help and the non-mod commands view?"},
	delay: {"": "Immediate", "30": "30 seconds", "60": "1 minute", "120": "2 minutes", "300": "5 minutes", "1800": "Half hour",
			"3600": "One hour", "7200": "Two hours", "*": "When should this be sent?"},
};
const toplevelflags = ["access", "visibility"];

function simple_to_advanced(e) {
	e.preventDefault();
	const elem = e.target.closest(".simpletext");
	const txt = elem.querySelector("input").value;
	elem.replaceWith(render_command(txt));
}

function simple_to_conditional(e) {
	e.preventDefault();
	const parent = e.currentTarget.closest(".simpletext");
	parent.replaceWith(render_command({
		conditional: "choose",
		message: parent.querySelector("input").value,
		otherwise: "",
	}));
}

function simple_text(msg) {
	return DIV({className: "simpletext"}, [
		INPUT({value: msg}),
		BUTTON({onclick: simple_to_advanced, title: "Customize flags for this line"}, "\u2699"),
		BUTTON({onclick: simple_to_conditional, title: "Make this conditional"}, "\u2753"),
	]);
}

function adv_add_elem(e) {
	e.target.parentNode.insertBefore(simple_text(""), e.target);
	e.preventDefault();
}

//Build an array of DOM elements that could include simple_texts. Calling render_command
//itself is guaranteed to offer the user flag space.
function text_array(prefix, msg) {
	const ret = (Array.isArray(msg) ? msg : [msg]).map(m =>
		(typeof m === "string") ? simple_text(m) : render_command(m)
	);
	if (prefix) ret.unshift(prefix);
	ret.push(BUTTON({onclick: adv_add_elem, title: "Add another line of text here"}, "+"));
	return ret;
}

const conditional_types = {
	string: {
		expr1: "Expression 1",
		expr2: "Expression 2",
		"": "The condition passes if (after variable substitution) the two are equal.",
	},
	number: {
		expr1: "Expression to evaluate",
		"": "The condition passes if the expression is nonzero. Use comparisons eg '$var$ > 100'.",
	},
	choose: {
		"": "Choose a type of condition.",
	},
};

//Recursively generate DOM elements to allow a command to be edited with full flexibility
function render_command(cmd, toplevel) {
	if (!cmd.message) cmd = {message: cmd};
	if (cmd.conditional) {
		//NOTE: This UI currently cannot handle (nor will it create) conditionals
		//with other flags. Instead, do the flags, and then have the conditional
		//as its sole message.
		const cond = conditional_types[cmd.conditional] || {"": "Unrecognized condition type!"};
		const rows = [TR([TD("Type:"), TD(SELECT({"data-flag": "conditional"}, [
			OPTION({value: "string"}, "String comparison"),
			OPTION({value: "number"}, "Numeric calculation"),
		]))])]; //TODO: Have a way to make something unconditional again
		rows[0].querySelector("[data-flag=conditional]").value = cmd.conditional;
		let desc = "";
		for (let key in cond) {
			if (key === "") desc = cond[key];
			else rows.push(TR([TD(cond[key]), INPUT({"data-flag": key, value: cmd[key] || "", className: "widetext"})]));
		}
		const td = TD(desc); td.setAttribute("colspan", 2);
		rows.push(TR(td));

		return FIELDSET({className: "optedmsg"}, [
			TABLE({border: 1, className: "flagstable"}, rows),
			FIELDSET({className: "optedmsg iftrue"}, text_array(LEGEND("If true:"), cmd.message || "")),
			FIELDSET({className: "optedmsg iffalse"}, text_array(LEGEND("If false:"), cmd.otherwise || "")),
		]);
	}
	//Handle flags
	const opts = [TR([TH("Option"), TH("Effect")])];
	let m = /^(\/[a-z]+) ([a-zA-Z$%]+)$/.exec(cmd.dest);
	if (m) {cmd.dest = m[1]; cmd.target = m[2];}
	for (let flg in flags) {
		if (!toplevel && toplevelflags.includes(flg)) continue;
		const opt = [];
		for (let o in flags[flg]) if (o !== "*")
		{
			const el = OPTION({value: o, selected: cmd[flg]+"" === o ? "1" : undefined}, flags[flg][o]);
			//Guarantee that the one marked with an empty string will be the first
			//It usually would be anyway, but make certain.
			if (o === "") opt.unshift(el); else opt.push(el);
		}
		opts.push(TR([
			TD(SELECT({"data-flag": flg}, opt)),
			TD(flags[flg]["*"]),
		]));
	}
	opts.push(TR([INPUT({"data-flag": "target", value: cmd.target || ""}), TD("For whisper, web, and variable destinations - who/what should it send to?")]));
	return FIELDSET({className: "optedmsg"}, text_array(DETAILS({className: "flagstable"}, [
		SUMMARY("Flags"),
		TABLE({border: 1}, opts),
	]), cmd.message));
}

on("click", "button.advview", e => {
	set_content("#command_details", render_command(commands[e.match.dataset.cmd], 1));
	set_content("#cmdname", "!" + e.match.dataset.cmd);
	document.getElementById("advanced_view").showModal();
});

on("change", "select[data-flag=conditional]", e => {
	//NOTE: Assumes that this does not have additional flags. They will be lost.
	const parent = e.match.closest(".optedmsg");
	const msg = get_command_details(parent);
	if (!msg.otherwise.length) msg.otherwise = ""; //Replace empty array with empty string to ensure we always get at least one input
	parent.replaceWith(render_command(msg));
});

//Recursively reconstruct the command info from the DOM - the inverse of render_command()
function get_command_details(elem) {
	if (elem.classList.contains("simpletext")) {
		//It's a simple input and can only have one value
		elem = elem.querySelector("input");
		if (elem && elem.value && elem.value !== "") return elem.value;
		return undefined; //Will suppress this from the resulting array
	}
	if (!elem.classList.contains("optedmsg")) return undefined;
	//Otherwise it's a full options-and-messages setup.
	const ret = {message: []};
	for (elem = elem.firstElementChild; elem; elem = elem.nextElementSibling) {
		if (elem.classList.contains("flagstable")) {
			elem.querySelectorAll("[data-flag]").forEach(flg => {
				if (flg.value !== "") ret[flg.dataset.flag] = flg.value;
			});
			if (ret.target && ret.dest && ret.dest[0] === "/") {
				ret.dest += " " + ret.target;
				delete ret.target;
			}
		}
		else if (elem.classList.contains("iftrue"))
			ret.message = get_command_details(elem).message;
		else if (elem.classList.contains("iffalse"))
			ret.otherwise = get_command_details(elem).message;
		else {
			const msg = get_command_details(elem);
			if (msg) ret.message.push(msg);
		}
	}
	if (ret.message.length === 1) ret.message = ret.message[0];
	//We could return ret.message if there are no other attributes, but
	//at the moment I can't be bothered. (Also, do it only if not toplevel.)
	//Worst case, we have some junk locally that won't matter; the server
	//will clean it up before next load anyhow.
	return ret;
}

on("click", "#save_advanced", async e => {
	let info = get_command_details(DOM("#command_details").firstChild);
	/*
	const cmd = commands[document.getElementById("cmdname").innerText.slice(1)];
	console.log("WAS:", cmd);
	console.log("NOW:", info);
	return;
	// */
	document.getElementById("advanced_view").close();
	const el = document.getElementById("cmdname").firstChild;
	const cmdname = el.nodeType === 3 ? el.data : el.value; //Not sure if text nodes' .data attribute is the best way to do this
	info.cmdname = cmdname;
	const res = await fetch("command_edit", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(info),
	});
	if (!res.ok) {console.error("Not okay response", res); return;}
	info = await res.json();
	//Scan the main table, find the command (if it existed), and remove it.
	//Then insert a replacement.
	for (const tr of DOM("#commandview").querySelectorAll("tr")) {
		if (tr.firstElementChild.tagName !== "TD") continue; //Header row
		const cmd = tr.firstElementChild.innerText.trim();
		if (cmd < cmdname) continue;
		if (cmd === cmdname) {tr.remove(); continue;}
		//We've found something that's further forward than the command
		//we want. Insert here. (Note that "Add: " is greater than any
		//command name starting "!", so it'll (correctly) trigger this.)
		//NOTE: It is highly unlikely that, after advanced editing, the
		//command will be safe for simple editing. So we assume it isn't,
		//and put just the plain text version.
		const lines = [];
		const cmdnobang = cmdname.slice(1);
		let idx = 0;
		function add_lines(msg) {
			if (typeof msg === "string")
				lines.push(msg, BR());
			else if (Array.isArray(msg))
				msg.forEach(add_lines);
			else if (typeof msg === "object") //Should always be true
				add_lines(msg.message);
			//Else ignore it, probably malformed or something
		}
		add_lines(info.message);
		lines.pop(); //Ditch the last BR
		tr.before(TR([
			TD(CODE(cmdname)),
			TD(CODE(lines)),
			TD(BUTTON({type: "button", className: "advview", "data-cmd": cmdnobang, title: "Advanced"}, "\u2699")),
		]));
		commands[cmdnobang] = info;
		break; //Only do this once :)
	}
});

on("click", 'a[href="/emotes"]', e => {
	e.preventDefault();
	window.open("/emotes", "emotes", "width=900, height=700");
});

on("click", "#examples", e => {
	e.preventDefault();
	document.getElementById("templates").showModal();
});
on("click", "#templates tbody tr", e => {
	e.preventDefault();
	document.getElementById("templates").close();
	const [cmd, text] = e.match.children;
	const cmdname = cmd.innerText.trim();
	const template = complex_templates[cmdname];
	if (template) {
		set_content("#command_details", render_command(template, 1));
		set_content("#cmdname", INPUT({value: cmdname}));
		document.getElementById("advanced_view").showModal();
		return;
	}
	document.forms[0].newcmd_name.value = cmdname;
	document.forms[0].newcmd_resp.value = text.innerText.trim();
});
