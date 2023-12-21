import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, DIV, FIGCAPTION, FIGURE, H3, IMG, INPUT, LABEL, LI, SPAN, STYLE, UL} = choc; //autoimport

const emote_backgrounds = {
	Light: "#ffffff",
	Dark: "#18181B",
	"Light HL": "#f2f2f2",
	"Dark HL": "#1f1f23",
	Black: "#000000",
};

set_content("#emotebg", [
	"Background: ",
	Object.entries(emote_backgrounds).map(([lbl, color]) => LABEL([
		INPUT({type: "radio", name: "emotebg", value: lbl.replaceAll(" ", "")}),
		" ", lbl,
		SPAN({class: "swatch", style: "background: " + color}),
	])),
]);
document.body.append(STYLE(Object.entries(emote_backgrounds).map(([lbl, color]) => `#img_dl.${lbl.replaceAll(" ", "")} img {
	background: ${color};
}`).join("\n")));
on("click", "input[name=emotebg]", e => DOM("#img_dl").classList = e.match.value);

function IMAGE(data, label) {
	return A({href: label + ".png"}, FIGURE([IMG({src: data, alt: ""}), FIGCAPTION(label)]));
}

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
		set_content("#emotetips", [
			resp.warnings && [H3("Warnings"), UL(resp.warnings.map(w => LI(w)))],
			resp.tips && [H3("Tips"), UL(resp.tips.map(w => LI(w)))],
			H3("Images"),
			DIV({id: "img_dl"}, [
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
