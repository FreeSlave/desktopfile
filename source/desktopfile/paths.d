/**
 * Getting applications paths where desktop files are stored.
 * 
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module desktopfile.paths;

private {
    import isfreedesktop;
    import xdgpaths;
    
    import std.algorithm;
    import std.array;
    import std.path;
    import std.range;
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
    @safe string[] applicationsPaths() nothrow {
        return xdgDataDirs("applications");
    }
    
    /**
     * Path where .desktop files can be stored without requiring of root privileges.
     * This function is defined only on freedesktop systems to avoid confusion with other systems that have data paths not compatible with Desktop Entry Spec.
     * Note: it does not check if returned path exists and appears to be directory.
     */
    @safe string writableApplicationsPath() nothrow {
        return xdgDataHome("applications");
    }
}
