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

__async__ array(mapping) list_files(int channelid, int|void include_blob) {
	array files = await(G->G->DB->list_channel_files(channelid, 0, include_blob));
	files = filter(files) {return __ARGS__[0]->metadata->owner == "imgbuilder";};
	//Sort by name...
	array names = lower_case(files->metadata->name[*]); sort(names, files);
	//... but group the large files before the small files.
	array smalls = files->metadata->pixwidth[*] < 200; sort(smalls, files);
	return files;
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	return (["files": await(list_files(channel->userid))]);
}

__async__ string|mapping file_upload_prepare(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {return msg;}

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

__async__ void wscmd_deletefile(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->id)) return;
	G->G->DB->delete_file(channel->userid, msg->id);
}

__async__ mapping wscmd_download(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array files = await(list_files(channel->userid, 1));
	int maxwidth = 1200; //TODO: Make these configurable.
	int xgap = 3, ygap = 3; //Pixels
	//First, a quick pass to build up the rows. Each row has a height, which is the tallest image in it.
	//A row is as many images as fit within the maxwidth.
	//It may be worth putting a hard break at a change of image width, but for now, not doing that.
	array rows = ({ });
	int curwid = -1, height = 0, totheight = 0;
	foreach (files, mapping file) {
		if (!file->data || file->data == "") continue; //Ignore any files that failed to upload
		file->image = Image.ANY._decode(file->data);
		if (file->metadata->pixwidth > curwid) {
			rows += ({({ })});
			curwid = maxwidth + xgap;
			totheight += height;
			height = 0;
		}
		rows[-1] += ({file});
		curwid -= file->metadata->pixwidth - xgap;
		//Slightly weird but whatever - the row height can always be found in row[-1]->height
		file->height = height = max(height, file->image->ysize);
	}
	//Okay. Now let's build up that image.
	if (!sizeof(rows)) return (["cmd": "nodownload"]); //Not responded to by the front end but it'll show up in the console
	totheight += rows[-1][-1]->height + ygap * (sizeof(rows) - 1);
	Image.Image image = Image.Image(maxwidth, totheight);
	Image.Image alpha = Image.Image(maxwidth, totheight);
	int ypos = 0;
	foreach (rows, array row) {
		int xpos = 0;
		foreach (row, mapping file) {
			image->paste_mask(file->image->image, file->image->alpha, xpos, ypos);
			alpha->paste_mask(file->image->alpha, file->image->alpha, xpos, ypos);
			xpos += file->image->xsize + xgap;
		}
		ypos += row[-1]->height + ygap;
	}
	werror("%O\n", image);
	string png = Image.PNG.encode(image, (["alpha": alpha]));
	string url = "data:image/png;base64," + MIME.encode_base64(png, 1);
	werror("URL is %d bytes\n", sizeof(url));
	return (["cmd": "download", "url": url]);
}

protected void create(string name) {::create(name);}
