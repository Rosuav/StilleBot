import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BR, BUTTON, DETAILS, DIV, FORM, H3, IMG, INPUT, LI, P, SPAN, SUMMARY, UL} = lindt; //autoimport
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

//FIXME: Make a hover piece in the corner that shows some good first steps.
//As they get completed, detect this and put a pretty green check mark against them.
//For each one, let the user click to see more information, and then have a pencil
//button to take them where they need to go.
const first_steps = {
	edit_config: "Set up basic title etc",
	edit_index: "Build out your landing page",
	new_page: "Create a new page",
	upload_images: "Upload some artwork!",
};

//Turn a flat list of files into a tree of DOM (Lindt) elements, gathering those in
//subdirectories into nested lists. Pass a describer function to generate list items
//(it gets the entire file object in case, but normally will just use the base name).
//NOTE: GitHub will shorthand things if you skip directory levels. Here we don't; if
//you go straight into /deep/path/to/files there will be individual levels to expand
//for each one. This is unlikely to be a major issue as directory levels won't be as
//common here.
function build_directory_tree(files, options) {
	if (!options) options = { };
	const describe = options.describe || (fn => fn); //Default to just showing the file name; the callback is also given the entire file object if needed
	const createnew = path => LI({style: "margin-top: 0.5em"},
		options.upload ? [
			FORM([
				"Upload new file: ",
				INPUT({class: "fileuploader", type: "file", multiple: 1, accept: "image/*", "data-prefix": path}),
			]),
			DIV({class: "filedropzone", "data-prefix": path}, "Or drop files here to upload"),
			DIV({id: "uploaderror", class: "hidden"}),
		] : [
			"Create new ",
			BUTTON({class: "new-file", type: "button", "data-prefix": path, "data-suffix": options.suffix || ""}, "\u{1F589}"),
			BUTTON({class: "edit-file", type: "button", "data-path": path}, "Load"),
		]
	);
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
					createnew(path),
				])])));
			}
			subdir = subdir[dir];
		}
		subdir[""].push(LI({key: parts[0]}, [
			describe(parts[0], file), " ",
			BUTTON({class: "edit-file", type: "button", "data-path": file.path, "data-viewsha": options.upload ? file.sha : ""},
				options.upload ? "\u{1F50D}" : "\u{1F589}"),
		]));
	}
	return UL([dirs[""], createnew("")]);
}

//NOTE: This uses the same CSS classes as the utils upload_to_library() system does, giving
//consistent display; since the upload implementation is incompatible, this means that the
//page cannot use both.
function upload(f, pfx) {
	const r = new FileReader();
	r.onload = () => {
		//The result is "data:TYPE/SUBTYPE;base64," followed by the base-64 data.
		//This is easier than reading the file as binary and then base-64ing it.
		//Since well-formed Base 64 data does not contain commas, we should be
		//safe splitting on the comma and taking the second half.
		const content = r.result.split(",")[1];
		ws_sync.send({cmd: "save_file", path: pfx + f.name, content});
	};
	r.readAsDataURL(f);
}

//TODO: Fast skip of the actual uploading work if we're in demo mode
on("change", ".fileuploader", e => {
	for (let f of e.match.files) upload(f, e.match.dataset.prefix);
	e.match.value = "";
});
on("dragover", ".filedropzone", e => e.preventDefault());
on("drop", ".filedropzone", e => {
	e.preventDefault();
	for (let f of e.dataTransfer.items) upload(f.getAsFile(), e.match.dataset.prefix);
});

let banner_fade = 0;
function show_banner(text, cls, fade) {
	clearTimeout(banner_fade);
	if (cls) DOM("#banner").className = cls;
	replace_content("#banner", [
		P(text),
	]).classList.add("visible");
	if (fade) banner_fade = setTimeout(() => DOM("#banner").classList.remove("visible"), fade * 1000);
}
//show_banner("Something's wrong", "error");
//show_banner("Something's happening", "pending");
//show_banner("Something's happened", "done", 10);

export function sockmsg_error(msg) {show_banner(msg.error, "error", 30);}

let last_build_status = "completed";
export function render(data) {
	if (!data.self) return replace_content("#content", P([
		"Your site is linked to your Twitch account. ",
		BUTTON({type: "button", class: "twitchlogin", "data-force": "1"}, "Log in with Twitch"),
	]));
	if (data.site.build_status && data.site.build_status !== last_build_status) {
		if (data.site.build_status === "completed") show_banner("Build complete!", "done", 10);
		else show_banner("Build " + data.site.build_status.replace("_", " ") + "...", "pending");
		last_build_status = data.site.build_status;
	}
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
				" ", BUTTON({type: "button", class: "opendlg", "data-dlg": "cnamedlg"}, "Configure URL"),
			]),
			P(["Your web site is always YOURS and Mustard Mine is always ready to hand control to you. ", BUTTON({type: "button", class: "opendlg", "data-dlg": "collabsdlg"}, "Manage ownership")]),
		],
		data.site.pages && [
			H3("Pages"), //Not a fan of calling this "pages" when the whole page is "pages". It's as bad as levels in D&D.
			P("Most of your web site is these sorts of pages. Use Markdown syntax for styling."),
			build_directory_tree(data.site.pages, {describe: fn => fn.replace(/\.md$/, ""), suffix: ".md"}),
		],
		[["media", "Media"], ["layouts", "Design/layout"], ["files", "Other files"]].map(([sec, title]) => {
			const files = data.site[sec];
			return files && DETAILS([
				SUMMARY(title),
				build_directory_tree(files, {upload: sec === "media"}),
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
	DOM("#filerename").hidden = false;
	DOM("#filedelete").hidden = false;
	DOM("#fileeditor").hidden = false;
	DOM("#fileimage").hidden = true;
	ace_editor.setValue(atob(msg.content));
	ace_editor.gotoLine(1);
	DOM("#editfiledlg").showModal();
	ace_editor.focus();
}

on("click", ".edit-file", e => {
	if (e.match.dataset.viewsha) {
		//Image-type content gets displayed, but can't be edited. Also, we don't have to fetch
		//the content in JS, we can simply reference it and have the browser load it.
		editing_file = {
			//Stubs to ensure that rename works - not full details
			path: e.match.dataset.path,
			sha: e.match.dataset.viewsha,
		};
		replace_content("#filetype", "Image");
		DOM("#filename").value = e.match.dataset.path;
		DOM("#filename").readOnly = true;
		DOM("#filerename").hidden = false;
		DOM("#filedelete").hidden = false;
		DOM("#fileeditor").hidden = true;
		const img = DOM("#fileimage"); img.hidden = false;
		img.src = ""; //Hide any previous image while the new one loads
		img.src = "https://raw.githubusercontent.com/mustardmine/" + ws_group.slice(1) + "/HEAD/" + e.match.dataset.path;
		DOM("#editfiledlg").showModal();
	} else ws_sync.send({cmd: "fetch_file", path: e.match.dataset.path}); //Display when we have the content
});
on("click", "#filesave", e => {
	show_banner("Saving file...", "pending");
	ws_sync.send({
		cmd: "save_file",
		path: editing_file.path || (editing_file.prefix + DOM("#filename").value + editing_file.suffix),
		content: btoa(ace_editor.getValue()),
		sha: editing_file.sha,
	});
	DOM("#editfiledlg").close();
});

on("click", ".new-file", e => {
	editing_file = {prefix: e.match.dataset.prefix || "", suffix: e.match.dataset.suffix || ""};
	const mode = getModeForPath(editing_file.suffix);
	ace_editor.session.setMode(mode.mode);
	replace_content("#filetype", mode.caption);
	DOM("#filename").value = "";
	DOM("#filename").readOnly = false;
	DOM("#filerename").hidden = true;
	DOM("#filedelete").hidden = true;
	DOM("#fileeditor").hidden = false;
	DOM("#fileimage").hidden = true;
	ace_editor.setValue("");
	DOM("#editfiledlg").showModal();
	ace_editor.focus();
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

//TODO: If you've made edits, what should we do? Offer to Save-As? Keep the unsaved changes but
//respect the underlying rename?
on("click", "#filerename", e => {
	DOM("#oldpath").value = DOM("#newpath").value = editing_file.path;
	DOM("#renamefiledlg").showModal();
});

on("submit", "#renamefiledlg form", e => {
	const newpath = DOM("#newpath").value;
	DOM("#renamefiledlg").close();
	if (newpath === editing_file.path) return; //No name change, don't close the editor
	ws_sync.send({cmd: "rename_file", oldpath: editing_file.path, newpath, sha: editing_file.sha});
	DOM("#editfiledlg").close(); //Will discard unsaved changes. Unideal but will do for now.
});
