import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {OPTION, SELECT, INPUT, LABEL, UL, LI, BUTTON, TR, TH, TD, SPAN} = choc;

const dlg = document.getElementById("editdlg");
on("click", "li", e => {
	if (dlg.open) return;
	let idx = [...e.match.parentNode.children].indexOf(e.match);
	let quote = quotes[idx]; if (!quote) return;
	set_content("#idx", "" + (idx + 1)); // because humans start counting at 1, silly things
	document.getElementById("text").value = quote.msg;
	set_content("#timestamp", new Date(quote.timestamp * 1000).toLocaleString());
	//TODO: Show the category image??
	set_content("#category", quote.game);
	set_content("#recorder", quote.recorder || "(unknown)");
	dlg.showModal();
});
