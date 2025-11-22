//This doesn't REALLY have anything to do with Stillebot, but it's the most convenient
//way to give people something that can run Pike code.
inherit http_websocket;
inherit hook;

constant markdown = #"# Image Builder - $$channel$$

Upload files to have them built up into a single image. Download the resulting image
and use it everywhere!

<div id=files></div>

<div class=uploadtarget></div>

[Download image](:#download)

> ### Rename file
> Names are not shown in the final image, but will affect the sort order.
>
> <form id=renameform method=dialog>
> <input type=hidden name=id>
> <label>Name: <input name=name size=50></label>
>
> [Apply](:#renamefile type=submit) [Cancel](:.dialog_close)
> </form>
{: tag=dialog #renamefiledlg}

";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	array files = await(G->G->DB->list_channel_files(channel->userid));
	files = filter(files) {return __ARGS__[0]->metadata->owner == "imgbuilder";};
	array names = lower_case(files->metadata->name[*]); sort(names, files);
	return (["files": files]);
}

@"is_mod": __async__ mapping|zero wscmd_upload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	msg->owner = "imgbuilder";
	mapping file = await(G->G->DB->prepare_file(channel->userid, conn->session->user->id, msg, 0));
	if (file->error) return (["cmd": "uploaderror", "name": msg->name, "error": file->error]);
	return (["cmd": "upload", "name": msg->name, "id": file->id]);
}

@hook_uploaded_file_edited: __async__ void file_uploaded(mapping file) {
	if (!file->metadata) {
		//File has been deleted. Purge all references to it.
		//Currently we don't track, so we don't know whether this was for us. Assume
		//it might have been, and push out updates.
		send_updates_all("#" + file->channel);
	}
	else if (file->metadata->owner == "imgbuilder") {
		if (!file->metadata->pixwidth && has_prefix(file->metadata->mimetype, "image/")) {
			//Get the blob and figure out its size
			mapping f = await(G->G->DB->get_file(file->id, 1));
			f->metadata->pixwidth = -1; //If anything goes wrong, don't retry.
			mixed ex = catch {
				object img = Image.ANY.decode(f->data);
				f->metadata->pixwidth = img->xsize();
			};
			if (ex) werror("Unable to set pixwidth: %O\n%s\n", f, describe_backtrace(ex));
			await(G->G->DB->update_file(file->id, f->metadata));
		}
		send_updates_all("#" + file->channel);
	}
}

__async__ void wscmd_renamefile(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->id) || !stringp(msg->name)) return;
	mapping file = await(G->G->DB->get_file(msg->id));
	if (!file || file->channel != channel->userid) return; //Not found in this channel.
	file->metadata->name = msg->name;
	G->G->DB->update_file(file->id, file->metadata);
}

protected void create(string name) {::create(name);}
