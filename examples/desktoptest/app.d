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
    return standardPaths(StandardPath.Applications) ~ writablePath(StandardPath.Desktop);
}

void main(string[] args)
{
    foreach(dir; desktopDirs().filter!(s => s.exists && s.isDir())) {
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