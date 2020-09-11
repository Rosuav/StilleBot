import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, INPUT, DIV, DETAILS, SUMMARY, TABLE, TR, TH, TD, SELECT, OPTION, FIELDSET} = choc;
const all_flags = "mode dest access visibility counter action".split(" ");

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
	dest: {"": "Chat", "/w $$": "Whisper", "/w %s": "Whisper to target", "/web %s": "Private access", "/web $$": "(unimplemented)",
		"*": "Where should the response be sent?"},
	access: {"": "Anyone", mod: "Mods only", "*": "Who should be able to use this command?"},
	visibility: {"": "Visible", hidden: "Hidden", "*": "Should the command be listed in !help and the non-mod commands view?"},
	action: {"": "Leave unchanged", "+1": "Increment", "=0": "Reset to zero", "*": "If looking at a counter, what should it do to it?"},
};
const toplevelflags = ["access", "visibility"];

function simple_to_advanced(e) {
	e.preventDefault();
	const elem = e.target.closest(".simpletext");
	const txt = elem.querySelector("input").value;
	elem.replaceWith(render_command(txt));
}

function simple_text(msg) {
	return DIV({className: "simpletext"}, [
		INPUT({value: msg}),
		BUTTON({onclick: simple_to_advanced}, "\u2699"),
	]);
}

function adv_add_elem(e) {
	e.target.parentNode.insertBefore(simple_text(""), e.target);
	e.preventDefault();
}

//Recursively generate DOM elements to allow a command to be edited with full flexibility
function render_command(cmd, toplevel) {
	if (!cmd.message) cmd = {message: cmd};
	//Handle flags
	const opts = [TR([TH("Option"), TH("Effect")])];
	for (let flg in flags) {
		if (!toplevel && toplevelflags.includes(flg)) continue;
		const opt = [];
		for (let o in flags[flg]) if (o !== "*")
			opt.push(OPTION({value: o, selected: cmd[flg] === o ? "1" : undefined}, flags[flg][o]))
		opts.push(TR([
			TD(SELECT({"data-flag": flg}, opt)),
			TD(flags[flg]["*"]),
		]));
	}
	opts.push(TR([INPUT({"data-flag": "counter"}), TD("Name of counter to manipulate (see !addcounter)")]));
	const info = [
		DETAILS({className: "flagstable"}, [
			SUMMARY("Flags"),
			TABLE({border: 1}, opts),
		]),
	];
	(typeof cmd.message === "string" ? [cmd.message] : cmd.message).forEach(msg => {
		if (typeof msg === "string") info.push(simple_text(msg));
		else return render_command(msg);
	});
	info.push(BUTTON({onclick: adv_add_elem}, "+"));
	return FIELDSET({className: "optedmsg"}, info);
}

on("click", "button.advview", e => {
	set_content("#command_details", render_command(commands[e.match.dataset.cmd], 1));
	set_content("#cmdname", "!" + e.match.dataset.cmd);
	document.getElementById("advanced_view").showModal();
});

//Recursively reconstruct the command info from the DOM - the inverse of render_command()
function get_command_details(elem, toplevel) {
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
		if (elem.classList.contains("flagstable"))
			elem.querySelectorAll("[data-flag]").forEach(flg => {
				if (flg.value !== "") ret[flg.dataset.flag] = flg.value;
			});
		else {
			const msg = get_command_details(elem);
			if (msg) ret.message.push(msg);
		}
	}
	if (ret.message.length === 1) ret.message = ret.message[0];
	//We could return ret.message if there are no other attributes, but
	//at the moment I can't be bothered. (Also, do it only if !toplevel.)
	return ret;
}

on("click", "#save_advanced", async e => {
	const info = get_command_details(DOM("#command_details").firstChild, 1);
	const flags = {};
	const cmd = commands[document.getElementById("cmdname").innerText.slice(1)];
	console.log("WAS:", cmd);
	console.log("NOW:", info);
	return;
	all_flags.forEach(flag => {
		const val = document.getElementById("flg_" + flag).value;
		if (val) flags[flag] = val;
		cmd[flag] = val; //Yes, this will put empty strings where nulls were. Won't matter, it's only local.
	});
	document.getElementById("advanced_view").close();
	flags.cmdname = document.getElementById("cmdname").innerText;
	const res = await fetch("command_edit", {
		method: "POST",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(flags),
	});
	if (!res.ok) {console.error("Not okay response", res); return;}
	console.log("Updated successfully.");
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
	document.getElementById("templates").close();
	const [cmd, text] = e.match.children;
	document.forms[0].newcmd_name.value = cmd.innerText;
	document.forms[0].newcmd_resp.value = text.innerText;
});

//Compat shim lifted from Mustard Mine
//For browsers with only partial support for the <dialog> tag, add the barest minimum.
//On browsers with full support, there are many advantages to using dialog rather than
//plain old div, but this way, other browsers at least have it pop up and down.
document.querySelectorAll("dialog").forEach(dlg => {
	if (!dlg.showModal) dlg.showModal = function() {this.style.display = "block";}
	if (!dlg.close) dlg.close = function() {this.style.removeProperty("display");}
});
on("click", ".dialog_cancel,.dialog_close", e => e.match.closest("dialog").close());
