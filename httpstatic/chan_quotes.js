import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, IMG, LI, TIME} = choc; //autoimport

const months = "January February March April May June July August September October November December".split(" ");

//NOT using render_item() as it expects stable IDs, where all we have is indices
function render_quote(item, idx) {
	const when = new Date(item.timestamp * 1000);
	let quote = item.msg;
	if (item.emoted) {
		const parts = item.emoted.split("\ufffa");
		quote = [parts.shift()]; //First part is the initial text.
		parts.forEach(p => {
			const [all, emoteid, emotename, text] = /^e(.*?):(.*?)\ufffb(.*)$/.exec(p);
			quote.push(IMG({src: "https://static-cdn.jtvnw.net/emoticons/v2/" + emoteid + "/default/light/1.0", alt: emotename, title: emotename}));
			quote.push(text);
		});
	}
	return LI({"data-idx": idx, ".quote": item}, [
		quote,
		" [" + item.game + ", ",
		TIME({datetime: when.toISOString()}, when.getDate() + " " + months[when.getMonth()] + " " + when.getFullYear()),
		"] ",
		BUTTON({class: "editbtn", type: "button"}, "\u{1F589}"),
	]);
}
export function render(data) {
	set_content("#quotelist", data.items.map((item, idx) => render_quote(item, idx)));
	DOM("#activatecommands").disabled = !data.can_activate;
	DOM("#deactivatecommands").disabled = !data.can_deactivate;
}

const dlg = document.getElementById("editdlg");
let editing_quote = 0;
on("click", ".editbtn", e => {
	const li = e.match.closest("[data-idx]");
	const idx = li.dataset.idx;
	let quote = li.quote; if (!quote) return;
	editing_quote = +idx + 1; // because humans start counting at 1, silly things
	set_content("#idx", "" + editing_quote);
	document.getElementById("text").value = quote.msg;
	set_content("#timestamp", new Date(quote.timestamp * 1000).toLocaleString());
	//TODO: Show the category image??
	set_content("#category", quote.game);
	set_content("#recorder", quote.recorder || "(unknown)");
	dlg.showModal();
});

on("click", "#update", e => ws_sync.send({cmd: "edit_quote", idx: editing_quote, msg: DOM("#text").value}));

on("click", "#activatecommands", e => ws_sync.send({cmd: "managecommands", state: 1}));
on("click", "#deactivatecommands", e => ws_sync.send({cmd: "managecommands", state: 0}));
DOM("#managequotes").hidden = false; //If you're a mod, this JS file will run. If not, it won't, and the management buttons will remain hidden.
