import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BUTTON, DETAILS, H3, IMG, LI, P, SUMMARY, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#content", [
		P([
			"Your site is linked to your Twitch account. ",
			//If you're logged in, show who you are, and allow switching. Otherwise, invite a login.
			data.self && [
				IMG({src: data.self.profile_image_url, class: "avatar", style: "vertical-align: middle"}),
				" ", B(data.self.display_name), " ",
			],
			BUTTON({type: "button", class: "twitchlogin", "data-force": "1"}, data.self ? "Not you?" : "Log in with Twitch"),
		]),
		!data.site.html_url ? P([
			//If there's no URL, either it hasn't loaded yet, or you don't have a repo.
			data.site._last_checked ? [
				"You don't currently have a web site set up this way. Would you like to start one? ",
				BUTTON({type: "button", id: "create_site"}, "Create site!"),
			] : "Loading web site information...",
		]) : [
			//NOTE: The html_url will be affected by the presence of a CNAME, so it should always be the "natural" URL.
			"You have a web site at ", A({href: data.site.html_url}, data.site.html_url),
			//TODO: Reword these nicely so people know "hey, you can refresh the page now"
			data.site.build_status && " Build: " + data.site.build_status,
		],
		data.site.pages && [
			H3("Pages"), //Not a fan of calling this "pages" when the whole page is "pages". It's as bad as levels in D&D.
			P("Most of your web site is these sorts of pages. Use Markdown syntax for styling."),
			UL([
				data.site.pages.map(page => LI([
					page.name.replace(/\.md$/, ""), " ",
					BUTTON({class: "edit-file", type: "button", "data-path": page.path}, "\u{1F589}"),
				])),
				LI({style: "margin-top: 0.5em"}, ["Create new page ", BUTTON({id: "new-file", type: "button", "data-extension": ".md"}, "\u{1F589}")]),
			]),
		],
		["Images", "Layouts", "Scripts", "Files"].map(sec => {
			const files = data.site[sec.toLowerCase()];
			return files && DETAILS([
				SUMMARY(sec === "Files" ? "Other files" : sec),
				UL([
					files.map(page => LI([
						page.name, " ",
						sec !== "Images" && BUTTON({class: "edit-file", type: "button", "data-path": page.path}, "\u{1F589}"),
					])),
					//TODO: Upload box
					sec !== "Images" && LI({style: "margin-top: 0.5em"}, ["Create new file ", BUTTON({id: "new-file", type: "button"}, "\u{1F589}")]),
				]),
			]);
		}),
	]);
}

on("click", "#create_site", e => ws_sync.send({cmd: "create_site"}));

//TODO: Make an actual form to do this. Tell people to first create a CNAME record at DNS provider, pointing to mustardmine.github.io
on("submit", "#set-cname-form", e => ws_sync.send({cmd: "set_cname", cname: e.match.elements.cname.value}));

let editing_file = null;
export function sockmsg_file_loaded(msg) {
	editing_file = msg;
	DOM("#filename").value = msg.name.replace(/\.md$/, "");
	DOM("#filename").readOnly = true;
	DOM("#filedelete").hidden = false;
	DOM("#filecontent").value = atob(msg.content);
	DOM("#editfiledlg").showModal();
}

on("click", ".edit-file", e => ws_sync.send({cmd: "fetch_file", path: e.match.dataset.path}));
on("click", "#filesave", e => {
	ws_sync.send({
		cmd: "save_file",
		path: editing_file.path || (DOM("#filename").value + editing_file.extension),
		content: btoa(DOM("#filecontent").value),
		sha: editing_file.sha
	});
	DOM("#editfiledlg").close();
});

on("click", "#new-file", e => {
	editing_file = {extension: e.match.dataset.extension || ""};
	DOM("#filename").value = "";
	DOM("#filename").readOnly = false;
	DOM("#filedelete").hidden = true;
	DOM("#filecontent").value = "";
	DOM("#editfiledlg").showModal();
});

on("click", "#filedelete", simpleconfirm("Delete this file? Links to it will go nowhere and the page will cease to exist.", e => {
	ws_sync.send({cmd: "delete_file", path: editing_file.path, sha: editing_file.sha});
	DOM("#editfiledlg").close();
}));
