import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, DIV, FIGCAPTION, FIGURE, H3, IMG, INPUT, LABEL, LI, SPAN, STYLE, UL} = choc; //autoimport

const emote_backgrounds = {
	Light: "#ffffff",
	Dark: "#18181B",
	"Light HL": "#f2f2f2",
	"Dark HL": "#1f1f23",
	Black: "#000000",
};

set_content("#emotebg", [
	"Background: ",
	Object.entries(emote_backgrounds).map(([lbl, color], idx) => LABEL([
		INPUT({type: "radio", name: "emotebg", value: lbl.replaceAll(" ", ""), checked: idx === 0}), //Pre-select the first option
		" ", lbl,
		SPAN({class: "swatch", style: "background: " + color}),
	])),
]);
document.body.append(STYLE(Object.entries(emote_backgrounds).map(([lbl, color]) => `#img_dl.${lbl.replaceAll(" ", "")} img {
	background: ${color};
}`).join("\n")));
on("click", "input[name=emotebg]", e => DOM("#img_dl").classList = e.match.value);

function IMAGE(data, label) {
	return A({href: data, download: label + ".png"}, FIGURE([IMG({src: data, alt: ""}), FIGCAPTION(label)]));
}

const embed = {
	"quantizing alpha levels": (p) => [p, BUTTON({type: "button", class: "opendlg", "data-dlg": "aqdlg", title: "How do you quantize alpha? Details."}, "(?)")],
};
function embeds(s) {
	const parts = s.split("||");
	if (parts.length === 1) return s;
	return parts.map(p => embed[p] ? embed[p](p) : p);
}

on("click", ".opendlg", e => document.getElementById(e.match.dataset.dlg).showModal());

async function upload(file) {
	set_content("#emotetips", "Analyzing...");
	DOM("#emotebg").hidden = false;
	const resp = await (await fetch("emotes?checkfile", {
		method: "POST",
		body: file,
		credentials: "same-origin",
	})).json();
	if (resp.error) return set_content("#emotetips", DIV({class: "error"}, resp.error));
	const reader = new FileReader();
	reader.readAsDataURL(file);
	reader.onloadend = () => {
		const rb = DOM("input[name=emotebg]:checked");
		set_content("#emotetips", [
			resp.warnings && [H3("Warnings"), UL(resp.warnings.map(w => LI(w)))],
			resp.tips && [H3("Tips"), UL(resp.tips.map(w => LI(embeds(w))))],
			H3("Images"),
			DIV({id: "img_dl", class: rb ? rb.value : ""}, [
				IMAGE(reader.result, "Original"),
				resp.downloads && resp.downloads.map(img => IMAGE(img.image, img.label)),
			]),
		]);
	};
}

on("change", "input[type=file]", e => {
	for (let f of e.match.files) upload(f);
	e.match.value = "";
});
on("dragover", ".filedropzone", e => e.preventDefault());
on("drop", ".filedropzone", e => {
	e.preventDefault();
	for (let f of e.dataTransfer.items) upload(f.getAsFile());
});
