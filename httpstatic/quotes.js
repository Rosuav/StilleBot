import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const { } = choc;

const dlg = document.getElementById("editdlg");
let editing_quote = 0;
let quote_li = null;
on("click", ".editbtn", e => {
	if (dlg.open) return;
	const li = e.match.closest("li");
	let idx = [...li.parentNode.children].indexOf(li);
	let quote = quotes[idx]; if (!quote) return;
	editing_quote = idx + 1; // because humans start counting at 1, silly things
	quote_li = li;
	set_content("#idx", "" + editing_quote);
	document.getElementById("text").value = quote.msg;
	set_content("#timestamp", new Date(quote.timestamp * 1000).toLocaleString());
	//TODO: Show the category image??
	set_content("#category", quote.game);
	set_content("#recorder", quote.recorder || "(unknown)");
	dlg.showModal();
});

on("click", "#update", async e => {
	console.log("Update");
	const text = document.getElementById("text").value;
	const res = await fetch("quote_edit", {
		method: "POST",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({id: editing_quote, msg: text}),
	});
	if (!res.ok) {console.error("Not okay response", res); return;}
	console.log("Updated successfully.");
	//Synthesize the updated quote text. Currently loses the date. (TODO: Preserve, don't synthesize.)
	set_content(quote_li, text + " [" + quotes[editing_quote - 1].game + "]");
	dlg.close();
});
