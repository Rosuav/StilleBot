import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, INPUT} = choc;
const all_flags = "mode dest access visibility counter action".split(" ");

on("click", "button.addline", e => {
	let parent = e.match.closest("td").previousElementSibling;
	parent.appendChild(BR());
	parent.appendChild(INPUT({
		name: e.match.dataset.cmd + "!" + e.match.dataset.idx++,
		className: "widetext"
	}));
});

on("click", "button.options", e => {
	const cmd = commands[e.match.dataset.cmd];
	//TODO: Handle all forms of recursive echoable-message
	//Currently handles the top level options only (and Pike is guaranteeing us a top-level object).
	set_content("#cmdname", "!" + e.match.dataset.cmd);
	all_flags.forEach(flag => {
		document.getElementById("flg_" + flag).value = cmd[flag] || "";
	});
	document.getElementById("options").showModal();
});

on("click", "#saveopts", async e => {
	const flags = {};
	const cmd = commands[document.getElementById("cmdname").innerText.slice(1)];
	all_flags.forEach(flag => {
		const val = document.getElementById("flg_" + flag).value;
		if (val) flags[flag] = val;
		cmd[flag] = val; //Yes, this will put empty strings where nulls were. Won't matter, it's only local.
	});
	document.getElementById("options").close();
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
