import std.stdio;
import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.process;

import desktopfile;

string[] applicationsDirs()
{
    string dataDirs = environment.get("XDG_DATA_DIRS");
    if (dataDirs.length) {
        return splitter(dataDirs, ':').map!(s => buildPath(s, "applications")).array;
    }
    return ["/usr/local/share/applications", "/usr/share/applications"];
}

void main(string[] args)
{
    foreach(dir; applicationsDirs()) {
        if (dir.exists && dir.isDir()) {
            foreach(entry; dir.dirEntries(SpanMode.depth).filter!(a => a.isFile() && a.extension == ".desktop")) {
                debug writeln(entry);
                try {
                    DesktopFile.loadFromFile(entry);
                }
                catch(DesktopFileException e) {
                    stderr.writefln("Error reading %s: at %s: %s", entry, e.lineNumber, e.msg);
                }
            }
        }
    }
}