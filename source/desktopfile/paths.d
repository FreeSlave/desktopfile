/**
 * Getting applications paths where desktop files are stored.
 * 
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module desktopfile.paths;

private {
    import desktopfile.isfreedesktop;
    
    import std.algorithm;
    import std.array;
    import std.exception;
    import std.path;
    import std.process : environment;
    import std.range;
    import std.string;
}

/**
 * Applications paths based on data paths. 
 * This function is available on all platforms, but requires dataPaths argument (e.g. C:\ProgramData\KDE\share on Windows)
 * Returns: Array of paths, based on dataPaths with "applications" directory appended.
 */
@trusted string[] applicationsPaths(Range)(Range dataPaths) if (isInputRange!Range && is(ElementType!Range : string)) {
    return dataPaths.map!(p => buildPath(p, "applications")).array;
}

///
unittest
{
    assert(equal(applicationsPaths(["share", buildPath("local", "share")]), [buildPath("share", "applications"), buildPath("local", "share", "applications")]));
}

static if (isFreedesktop)
{
    /**
     * ditto, but returns paths based on known data paths.
     * This function is defined only on freedesktop systems to avoid confusion with other systems that have data paths not compatible with Desktop Entry Spec.
     */
    @trusted string[] applicationsPaths() nothrow {
        string[] result;
        
        collectException(splitter(environment.get("XDG_DATA_DIRS"), ':').map!(p => buildPath(p, "applications")).array, result);
        if (result.empty) {
            result = ["/usr/local/share/applications", "/usr/share/applications"];
        }
        
        string homeAppDir = writableApplicationsPath();
        if(homeAppDir.length) {
            result = homeAppDir ~ result;
        }
        return result;
    }
    
    ///
    unittest
    {
        try {
            environment["XDG_DATA_DIRS"] = "/myuser/share:/myuser/share/local";
            environment["XDG_DATA_HOME"] = "/home/myuser/share";
            
            assert(equal(applicationsPaths(), ["/home/myuser/share/applications", "/myuser/share/applications", "/myuser/share/local/applications"]));
            
            environment["XDG_DATA_DIRS"] = null;
            assert(equal(applicationsPaths(), ["/home/myuser/share/applications", "/usr/local/share/applications", "/usr/share/applications"]));
        }
        catch (Exception e) {
            import std.stdio;
            stderr.writeln("environment error in unittest", e.msg);
        }
    }
    
    /**
     * Path where .desktop files can be stored without requiring of root privileges.
     * This function is defined only on freedesktop systems to avoid confusion with other systems that have data paths not compatible with Desktop Entry Spec.
     * Note: it does not check if returned path exists and appears to be directory.
     */
    @trusted string writableApplicationsPath() nothrow {
        string dir;
        collectException(environment.get("XDG_DATA_HOME"), dir);
        if (!dir.length) {
            string home;
            collectException(environment.get("HOME"), home);
            if (home.length) {
                return buildPath(home, ".local/share/applications");
            }
        } else {
            return buildPath(dir, "applications");
        }
        return null;
    }
    
    ///
    unittest
    {
        try {
            environment["XDG_DATA_HOME"] = "/home/myuser/share";
            assert(writableApplicationsPath() == "/home/myuser/share/applications");
            
            environment["XDG_DATA_HOME"] = null;
            environment["HOME"] = "/home/myuser";
            assert(writableApplicationsPath() == "/home/myuser/.local/share/applications");
        }
        catch(Exception e) {
            import std.stdio;
            stderr.writeln("environment error in unittest", e.msg);
        }
    }
}
