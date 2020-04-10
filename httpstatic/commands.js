import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, INPUT} = choc;

//TODO: Chocify this code
document.querySelectorAll("button.addline").forEach(btn => btn.onclick = e => {
	const inp = document.createElement("input");
	inp.name = e.currentTarget.dataset.cmd + "!" + e.currentTarget.dataset.idx++;
	inp.className = "widetext";
	let parent = e.currentTarget.parentElement;
	parent = parent.previousElementSibling;
	parent.appendChild(document.createElement("br"));
	parent.appendChild(inp);
});
document.getElementById("emotepicker").onclick = e => {
	e.preventDefault();
	window.open("/emotes", "emotes", "width=900, height=700");
};
//Will bomb when not logged in. This isn't a problem other than that it's noisy
//on the console. TODO: Remove most of this code so it doesn't even need to be
//downloaded to non-authenticated users.
document.getElementById("examples").onclick = e => {
	e.preventDefault();
	document.getElementById("templates").showModal();
};
document.querySelectorAll("#templates tbody tr").forEach(tr => tr.onclick = e => {
	document.getElementById("templates").close();
	const [cmd, text] = e.currentTarget.children;
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
