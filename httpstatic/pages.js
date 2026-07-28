import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BR, BUTTON, DETAILS, FORM, H3, IMG, INPUT, LI, P, SPAN, SUMMARY, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";
import "https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.2/ace.min.js"; //Editor with syntax highlighting
window.ace.config.set("basePath", "https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.2/");
//For some reason, we need to first import, THEN require.
import "https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.2/ext-modelist.js";
const getModeForPath = window.require("ace/ext/modelist").getModeForPath;

const ace_editor = window.ace.edit("fileeditor", {
	theme: "ace/theme/tomorrow",
	selectionStyle: "text",
});
window.ace_editor = ace_editor; //Allow interactive tinkering

//Turn a flat list of files into a tree of DOM (Lindt) elements, gathering those in
//subdirectories into nested lists. Pass a describer function to generate list items
//(it gets the entire file object in case, but normally will just use the base name).
//NOTE: GitHub will shorthand things if you skip directory levels. Here we don't; if
//you go straight into /deep/path/to/files there will be individual levels to expand
//for each one. This is unlikely to be a major issue as directory levels won't be as
//common here.
function build_directory_tree(files, describe, suffix) {
	const dirs = {"": []};
	for (let file of files) {
		const parts = file.path.split("/");
		let subdir = dirs;
		let path = "";
		while (parts.length > 1) {
			const dir = parts.shift();
			path += dir + "/";
			if (!subdir[dir]) {
				subdir[dir] = { };
				subdir[""].push(LI({key: dir}, DETAILS([SUMMARY(dir + "/"), UL([
					subdir[dir][""] = [],
					LI({style: "margin-top: 0.5em"}, [
						"Create new ",
						BUTTON({class: "new-file", type: "button", "data-prefix": path, "data-suffix": suffix || ""}, "\u{1F589}"),
					]),
				])])));
			}
			subdir = subdir[dir];
		}
		subdir[""].push(LI({key: parts[0]}, [
			describe(parts[0], file), " ",
			BUTTON({class: "edit-file", type: "button", "data-path": file.path}, "\u{1F589}"),
		]));
	}
	return UL([
		dirs[""],
		LI({style: "margin-top: 0.5em"}, [
			"Create new ",
			BUTTON({class: "new-file", type: "button", "data-prefix": "", "data-suffix": suffix || ""}, "\u{1F589}"),
		]),
	]);
}

export function render(data) {
	if (!data.self) return replace_content("#content", P([
		"Your site is linked to your Twitch account. ",
		BUTTON({type: "button", class: "twitchlogin", "data-force": "1"}, "Log in with Twitch"),
	]));
	replace_content("#content", [
		P([
			"Your site is linked to your Twitch account. ",
			//If you're logged in, show who you are, and allow switching. Otherwise, invite a login.
			IMG({src: data.self.profile_image_url, class: "avatar", style: "vertical-align: middle"}),
			" ", B(data.self.display_name), " ",
			data.self.fake ? [SPAN({style: "display: inline-block; width: 2em"}), "Want to create your own web site? ", A({href: "pages"}, "Go live!")]
			: BUTTON({type: "button", class: "twitchlogin", "data-force": "1"}, "Not you?"),
		]),
		!data.site.html_url ? P([
			//If there's no URL, either it hasn't loaded yet, or you don't have a repo.
			data.site._last_checked ? [
				"You don't currently have a web site set up this way. Would you like to start one? ",
				BUTTON({type: "button", id: "create_site"}, "Create site!"),
				" Alternatively, ", A({href: "pages?demo"}, "explore in demo mode"),
			] : "Loading web site information...",
		]) : [
			P([
				//NOTE: The html_url will be affected by the presence of a CNAME, so it should always be the "natural" URL.
				"You have a web site at ", A({href: data.site.html_url}, data.site.html_url),
				//TODO: Reword these nicely so people know "hey, you can refresh the page now"
				data.site.build_status && " Build: " + data.site.build_status,
				" ", BUTTON({type: "button", class: "opendlg", "data-dlg": "cnamedlg"}, "Configure URL"),
			]),
			P(["Your web site is always YOURS and Mustard Mine is always ready to hand control to you. ", BUTTON({type: "button", class: "opendlg", "data-dlg": "collabsdlg"}, "Manage ownership")]),
		],
		data.site.pages && [
			H3("Pages"), //Not a fan of calling this "pages" when the whole page is "pages". It's as bad as levels in D&D.
			P("Most of your web site is these sorts of pages. Use Markdown syntax for styling."),
			build_directory_tree(data.site.pages, fn => fn.replace(/\.md$/, ""), ".md"),
		],
		[["images", "Images"], ["layouts", "Design/layout"], ["files", "Other files"]].map(([sec, title]) => {
			const files = data.site[sec];
			return files && DETAILS([
				SUMMARY(title),
				build_directory_tree(files, fn => fn),
			]);
		}),
	]);
	if (data.site.collab) replace_content("#collaborators", [
		P(["In order to manage your web site independently of Mustard Mine, you will need a ",
			A({href: "https://github.com/"}, "GitHub account"), "."]),
		data.site.collab.length && [
			P("The following GitHub users have permission to manage your web site:"),
			UL(data.site.collab.map(user => LI({"data-username": user.username}, [
				IMG({src: user.avatar, class: "avatar", style: "vertical-align: middle"}),
				" ", B(user.username), " ",
				user.pending ? ["(awaiting confirmation) ", BUTTON({class: "removecollab"}, "Cancel invitation")]
				: [
					BUTTON({class: "removecollab"}, "Remove"),
					BUTTON({class: "transfer"}, "Transfer ownership"),
				]
			]))),
		],
		FORM({id: "addcollaborator"}, [
			"Enter your GitHub user name to be given control: ",
			BR(),
			INPUT({name: "username", size: 30}), " ",
			BUTTON({type: "submit"}, "Grant permission"),
			BR(),
			"You will receive an email with a confirmation button.",
		]),
	]);
}

on("click", "#create_site", e => ws_sync.send({cmd: "create_site"}));

let editing_file = null;
export function sockmsg_file_loaded(msg) {
	editing_file = msg;
	const mode = getModeForPath(msg.name);
	ace_editor.session.setMode(mode.mode);
	replace_content("#filetype", mode.caption);
	DOM("#filename").value = msg.name.replace(/\.md$/, "");
	DOM("#filename").readOnly = true;
	DOM("#filedelete").hidden = false;
	ace_editor.setValue(atob(msg.content));
	ace_editor.gotoLine(1);
	DOM("#editfiledlg").showModal();
	ace_editor.focus();
}

on("click", ".edit-file", e => ws_sync.send({cmd: "fetch_file", path: e.match.dataset.path}));
on("click", "#filesave", e => {
	ws_sync.send({
		cmd: "save_file",
		path: editing_file.path || (editing_file.prefix + DOM("#filename").value + editing_file.suffix),
		content: btoa(ace_editor.getValue()),
		sha: editing_file.sha
	});
	DOM("#editfiledlg").close();
});

on("click", ".new-file", e => {
	editing_file = {prefix: e.match.dataset.prefix || "", suffix: e.match.dataset.suffix || ""};
	const mode = getModeForPath(e.match.dataset.suffix || "");
	ace_editor.session.setMode(mode.mode);
	replace_content("#filetype", mode.caption);
	DOM("#filename").value = "";
	DOM("#filename").readOnly = false;
	DOM("#filedelete").hidden = true;
	ace_editor.setValue("");
	DOM("#editfiledlg").showModal();
});

on("click", "#filedelete", simpleconfirm("Delete this file? Links to it will go nowhere and the page will cease to exist.", e => {
	ws_sync.send({cmd: "delete_file", path: editing_file.path, sha: editing_file.sha});
	DOM("#editfiledlg").close();
}));

on("submit", "#addcollaborator", e => {
	e.preventDefault();
	const username = e.match.elements.username.value;
	if (username !== "") ws_sync.send({cmd: "add_collaborator", username});
});

on("click", ".removecollab", simpleconfirm("Remove this GitHub user's access to your web site?",
	e => ws_sync.send({cmd: "remove_collaborator", username: e.match.closest_data("username")})));

on("click", ".transfer", simpleconfirm("CAUTION: Transferring repository ownership is difficult to undo! Really transfer control?",
	e => ws_sync.send({cmd: "transfer_repository", username: e.match.closest_data("username")})));

on("click", "#setcname", simpleconfirm("Ensure that you have created the DNS record first.",
	e => ws_sync.send({cmd: "set_cname", cname: DOM("#cname").value})));
