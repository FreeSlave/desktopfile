import std.stdio;
import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.process;

import desktopfile;

void main(string[] args)
{
    string[] desktopDirs;
    
    version(OSX) {} else version(Posix) {
        import standardpaths;
        
        desktopDirs = applicationsPaths() ~ writablePath(StandardPath.desktop);
    } else version(Windows) {
        try {
            auto root = environment.get("SYSTEMDRIVE", "C:");
            auto kdeDir = root ~ `\ProgramData\KDE\share\applications`;
            if (kdeDir.isDir) {
                desktopDirs = [kdeDir];
            }
        } catch(Exception e) {
            
        }
    }
    
    if (args.length > 1) {
        desktopDirs = args[1..$];
    }
    
    if (!desktopDirs.length) {
        writeln("No desktop directories given nor could be detected");
        writefln("Usage: %s [DIR]...", args[0]);
        return;
    }
    
    writefln("Using directories: %-(%s, %)", desktopDirs);

    foreach(dir; desktopDirs.filter!(s => s.exists && s.isDir())) {
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
