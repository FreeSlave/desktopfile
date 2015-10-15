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
        
        string[] dataPaths = standardPaths(StandardPath.data);
        
        desktopDirs = applicationsPaths() ~ dataPaths.map!(s => buildPath(s, "desktop-directories")).array ~ dataPaths.map!(s => buildPath(s, "templates")).array ~ writablePath(StandardPath.desktop);
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
        writefln("Usage: %s [DIRECTORY]...", args[0]);
        return;
    }
    
    writefln("Using directories: %-(%s, %)", desktopDirs);

    foreach(dir; desktopDirs.filter!(s => s.exists && s.isDir())) {
        foreach(entry; dir.dirEntries(SpanMode.depth).filter!(a => a.isFile() && (a.extension == ".desktop" || a.extension == ".directory"))) {
            debug writeln(entry);
            try {
                auto df = new DesktopFile(entry);
                if (!df.execString().empty) {
                    auto execArgs = df.expandExecString();
                }
            }
            catch(IniLikeException e) {
                stderr.writefln("Error reading %s: at %s: %s", entry, e.lineNumber, e.msg);
            }
            catch(DesktopExecException e) {
                stderr.writefln("Error while expanding Exec value of %s: %s", entry, e.msg);
            }
            catch(Exception e) {
                stderr.writefln("Error reading %s: %s", entry, e.msg);
            }
        }
    }
}
