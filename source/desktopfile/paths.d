/**
 * Getting applications paths where desktop files are stored.
 *
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also:
 *  $(LINK2 https://www.freedesktop.org/wiki/Specifications/desktop-entry-spec/, Desktop Entry Specification)
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

version(unittest) {
    import std.process : environment;

    package struct EnvGuard
    {
        this(string env, string newValue) {
            envVar = env;
            envValue = environment.get(env);
            environment[env] = newValue;
        }

        ~this() {
            if (envValue is null) {
                environment.remove(envVar);
            } else {
                environment[envVar] = envValue;
            }
        }

        string envVar;
        string envValue;
    }
}

/**
 * Applications paths based on data paths.
 * This function is available on all platforms, but requires dataPaths argument (e.g. C:\ProgramData\KDE\share on Windows)
 * Returns: Array of paths, based on dataPaths with "applications" directory appended.
 */
string[] applicationsPaths(Range)(Range dataPaths) if (isInputRange!Range && is(ElementType!Range : string)) {
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
        return xdgAllDataDirs("applications");
    }

    ///
    unittest
    {
        import std.process : environment;
        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME", "/home/user/data");
        auto dataDirsGuard = EnvGuard("XDG_DATA_DIRS", "/usr/local/data:/usr/data");

        assert(applicationsPaths() == ["/home/user/data/applications", "/usr/local/data/applications", "/usr/data/applications"]);
    }

    /**
     * Path where .desktop files can be stored by user.
     * This function is defined only on freedesktop systems.
     * Note: it does not check if returned path exists and appears to be directory.
     */
    @safe string writableApplicationsPath() nothrow {
        return xdgDataHome("applications");
    }

    ///
    unittest
    {
        import std.process : environment;
        auto dataHomeGuard = EnvGuard("XDG_DATA_HOME", "/home/user/data");
        assert(writableApplicationsPath() == "/home/user/data/applications");
    }
}
