# Assemble mbox from evolution cache

There are times when you need to restore an email from
[evolution's](http://projects.gnome.org/evolution/) cache. This script does
that and turns cached message into an mbox file.

## Usage

Check out this git repo

    git clone https://github.com/lutter/assembox.git
    cd assembox

Make sure you have ruby installed and simply run `assembox` like this

    ./bin/assembox -d ~/.cache/evolution/mail/7/INBOX -o /tmp/mails.mbox

The argument to `-d` is a evolution cache directory. You can use `-m` to
restore just one message from that directory.

## How it works

This has worked for me; if it breaks for you, you get to keep both parts.

The way evolution organizes a cache directory (in version 3.6.4) is that
plain messages get stored in a file 'N.' where N is a number; MIME messages
are stored in a number of files: the first is 'N.HEADER' which contains the
message headers, and then for each part files 'N(.M)\*.MIME' for the MIME
headers for a part and 'N(.M)\*' for the body of a part. As the overall
message can form a tree of parts, fun ensues restoring the tree and
figuring out the right MIME boundary strings.

Restoring a message into an mbox amounts to little more than cating the
files into the mbox file, together with a little extra padding like a
'From' line, the right MIME boundaries, and plenty of blank lines in the
right places.

## License

This script is licensed under the GPL v3; see the file LICENSE for details
