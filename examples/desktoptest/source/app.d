import std.stdio;
import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.process;

import standardpaths;
import desktopfile;

string[] desktopDirs()
{
    return applicationsPaths() ~ writablePath(StandardPath.Desktop);
}

void main(string[] args)
{
    foreach(dir; desktopDirs().filter!(s => s.exists && s.isDir())) {
        foreach(entry; dir.dirEntries(SpanMode.depth).filter!(a => a.isFile() && a.extension == ".desktop")) {
            debug writeln(entry);
            try {
                new DesktopFile(entry);
            }
            catch(IniLikeException e) {
                stderr.writefln("Error reading %s: at %s: %s", entry, e.lineNumber, e.msg);
            }
            catch(Exception e) {
                stderr.writefln("Error reading %s: %s", entry, e.msg);
            }
        }
    }
}
