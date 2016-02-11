/**
 * Utility functions for reading and executing desktop files.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module desktopfile.utils;

public import inilike.common;
public import inilike.range;

package {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.exception;
    import std.file;
    import std.path;
    import std.process;
    import std.range;
    import std.stdio;
    import std.string;
    import std.traits;
    import std.typecons;
    
    static if( __VERSION__ < 2066 ) enum nogc = 1;
    
    import desktopfile.isfreedesktop;
}

package @trusted File getNullStdin()
{
    version(Posix) {
        return File("/dev/null", "rb");
    } else {
        return std.stdio.stdin;
    }
}

package @trusted File getNullStdout()
{
    version(Posix) {
        return File("/dev/null", "wb");
    } else {
        return std.stdio.stdout;
    }
}

package @trusted File getNullStderr()
{
    version(Posix) {
        return File("/dev/null", "wb");
    } else {
        return std.stdio.stderr;
    }
}

package @trusted Pid execProcess(string[] args, string workingDirectory = null)
{
    static if( __VERSION__ < 2066 ) {
        return spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.none);
    } else {
        return spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.none, workingDirectory);
    }
}

/**
 * Exception thrown when "Exec" value of DesktopFile or DesktopAction is invalid.
 */
class DesktopExecException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
    }
}

/**
 * Unescape Exec argument as described in [specification](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html).
 * Returns: Unescaped string.
 */
@trusted string unescapeExecArgument(string arg) nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('s', ' '),
       tuple('n', '\n'),
       tuple('r', '\r'),
       tuple('t', '\t'),
       tuple('"', '"'),
       tuple('\'', '\''),
       tuple('\\', '\\'),
       tuple('>', '>'),
       tuple('<', '<'),
       tuple('~', '~'),
       tuple('|', '|'),
       tuple('&', '&'),
       tuple(';', ';'),
       tuple('$', '$'),
       tuple('*', '*'),
       tuple('?', '?'),
       tuple('#', '#'),
       tuple('(', '('),
       tuple(')', ')'),
       tuple('`', '`'),
    ];
    return doUnescape(arg, pairs);
}

///
unittest
{
    assert(unescapeExecArgument("simple") == "simple");
    assert(unescapeExecArgument(`with\&\"escaped\"\?symbols\$`) == `with&"escaped"?symbols$`);
}

private @trusted string unescapeQuotedArgument(string value) nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('`', '`'),
       tuple('$', '$'),
       tuple('"', '"'),
       tuple('\\', '\\')
    ];
    return doUnescape(value, pairs);
}

/**
 * Unquote Exec value into an array of escaped arguments. 
 * If an argument was quoted then unescaping of quoted arguments is applied automatically. Note that unescaping of quoted argument is not the same as unquoting argument in general. Read more in [specification](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html).
 * Throws:
 *  DesktopExecException if string can't be unquoted (e.g. no pair quote).
 * Note:
 *  Although Desktop Entry Specification says that arguments must be quoted by double quote, for compatibility reasons this implementation also recognizes single quotes.
 */
@trusted auto unquoteExecString(string value) pure
{
    import std.uni : isWhite;
    
    string[] result;
    size_t i;
    
    while(i < value.length) {
        if (isWhite(value[i])) {
            i++;
        } else if (value[i] == '"' || value[i] == '\'') {
            char delimeter = value[i];
            size_t start = ++i;
            bool inQuotes = true;
            bool wasSlash;
            
            while(i < value.length) {
                if (value[i] == '\\' && value.length > i+1 && value[i+1] == '\\') {
                    i+=2;
                    wasSlash = true;
                    continue;
                }
                
                if (value[i] == delimeter && (value[i-1] != '\\' || (value[i-1] == '\\' && wasSlash) )) {
                    inQuotes = false;
                    break;
                }
                wasSlash = false;
                i++;
            }
            if (inQuotes) {
                throw new DesktopExecException("Missing pair quote");
            }
            result ~= value[start..i].unescapeQuotedArgument();
            i++;
            
        } else {
            size_t start = i;
            while(i < value.length && !isWhite(value[i])) {
                i++;
            }
            result ~= value[start..i];
        }
    }
    
    return result;
}

///
unittest 
{
    assert(equal(unquoteExecString(``), string[].init));
    assert(equal(unquoteExecString(`   `), string[].init));
    assert(equal(unquoteExecString(`"" "  "`), [``, `  `]));
    
    assert(equal(unquoteExecString(`cmd arg1  arg2   arg3   `), [`cmd`, `arg1`, `arg2`, `arg3`]));
    assert(equal(unquoteExecString(`"cmd" arg1 arg2  `), [`cmd`, `arg1`, `arg2`]));
    
    assert(equal(unquoteExecString(`"quoted cmd"   arg1  "quoted arg"  `), [`quoted cmd`, `arg1`, `quoted arg`]));
    assert(equal(unquoteExecString(`"quoted \"cmd\"" arg1 "quoted \"arg\""`), [`quoted "cmd"`, `arg1`, `quoted "arg"`]));
    
    assert(equal(unquoteExecString(`"\\\$" `), [`\$`]));
    assert(equal(unquoteExecString(`"\\$" `), [`\$`]));
    assert(equal(unquoteExecString(`"\$" `), [`$`]));
    assert(equal(unquoteExecString(`"$"`), [`$`]));
    
    assert(equal(unquoteExecString(`"\\" `), [`\`]));
    assert(equal(unquoteExecString(`"\\\\" `), [`\\`]));
    
    assert(equal(unquoteExecString(`'quoted cmd' arg`), [`quoted cmd`, `arg`]));
    
    assertThrown!DesktopExecException(unquoteExecString(`cmd "quoted arg`));
}


/**
 * Convenient function used to unquote and unescape Exec value into an array of arguments.
 * Note:
 *  Parsed arguments still may contain field codes that should be appropriately expanded before passing to spawnProcess.
 * Throws:
 *  DesktopExecException if string can't be unquoted.
 * See_Also:
 *  unquoteExecString, unescapeExecArgument
 */
@trusted string[] parseExecString(string execString) pure
{
    return execString.unquoteExecString().map!(unescapeExecArgument).array;
}

///
unittest
{
    assert(equal(parseExecString(`"quoted cmd" new\nline "quoted\\\\arg" slash\\arg`), ["quoted cmd", "new\nline", `quoted\arg`, `slash\arg`]));
}

/**
 * Expand Exec arguments (usually returned by parseExecString) replacing field codes with given values, making the array suitable for passing to spawnProcess. Deprecated field codes are ignored.
 * Note:
 *  Returned array may be empty and should be checked before passing to spawnProcess.
 * Params:
 * execArgs = array of unquoted and unescaped arguments.
 *  urls = array of urls or file names that inserted in the place of %f, %F, %u or %U field codes. For %f and %u only the first element of array is used.
 *  iconName = icon name used to substitute %i field code by --icon iconName.
 *  name = name of application used that inserted in the place of %c field code.
 *  fileName = name of desktop file that inserted in the place of %k field code.
 * Throws:
 *  DesktopExecException if command line contains unknown field code.
 * See_Also:
 *  parseExecString
 */
@trusted string[] expandExecArgs(in string[] execArgs, in string[] urls = null, string iconName = null, string name = null, string fileName = null) pure
{
    string[] toReturn;
    foreach(token; execArgs) {
        if (token == "%f") {
            if (urls.length) {
                toReturn ~= urls.front;
            }
        } else if (token == "%F") {
            toReturn ~= urls;
        } else if (token == "%u") {
            if (urls.length) {
                toReturn ~= urls.front;
            }
        } else if (token == "%U") {
            toReturn ~= urls;
        } else if (token == "%i") {
            if (iconName.length) {
                toReturn ~= "--icon";
                toReturn ~= iconName;
            }
        } else if (token == "%c") {
            toReturn ~= name;
        } else if (token == "%k") {
            toReturn ~= fileName;
        } else if (token == "%d" || token == "%D" || token == "%n" || token == "%N" || token == "%m" || token == "%v") {
            continue;
        } else {
            if (token.length >= 2 && token[0] == '%') {
                if (token[1] == '%') {
                    toReturn ~= token[1..$];
                } else {
                    throw new DesktopExecException("Unknown field code: " ~ token);
                }
            } else {
                toReturn ~= token;
            }
        }
    }
    
    return toReturn;
}

///
unittest
{
    assert(expandExecArgs(["program name", "%%f", "%f", "%i"], ["one", "two"], "folder") == ["program name", "%f", "one", "--icon", "folder"]);
    assertThrown!DesktopExecException(expandExecArgs(["program name", "%y"]));
}

/**
 * Unquote, unescape Exec string and expand field codes substituting them with appropriate values.
 * Throws:
 *  DesktopExecException if string can't be unquoted, unquoted command line is empty or it has unknown field code.
 * See_Also:
 *  expandExecArgs, parseExecString
 */
@trusted string[] expandExecString(string execString, in string[] urls = null, string iconName = null, string name = null, string fileName = null) pure
{
    auto execArgs = parseExecString(execString);
    if (execArgs.empty) {
        throw new DesktopExecException("No arguments. Missing or empty Exec value");
    }
    return expandExecArgs(execArgs, urls, iconName, name, fileName);
}

///
unittest
{
    assert(expandExecString(`"quoted program" %i -w %c -f %k %U %D %u %f %F`, ["one", "two"], "folder", "Программа", "/example.desktop") == ["quoted program", "--icon", "folder", "-w", "Программа", "-f", "/example.desktop", "one", "two", "one", "one", "one", "two"]);
    
    assertThrown!DesktopExecException(expandExecString(`program %f %y`)); //%y is unknown field code.
    assertThrown!DesktopExecException(expandExecString(``));
}

/**
 * Detect command which will run program in terminal emulator.
 * On Freedesktop it looks for x-terminal-emulator first. If found ["/path/to/x-terminal-emulator", "-e"] is returned.
 * Otherwise it looks for xdg-terminal. If found ["/path/to/xdg-terminal"] is returned.
 * If all guesses failed, it uses ["xterm", "-e"] as fallback.
 * Note: This function always returns empty array on non-freedesktop systems.
 */
string[] getTerminalCommand() nothrow @trusted 
{
    static if (isFreedesktop) {
        static string checkExecutable(string filePath) nothrow {
            import core.sys.posix.unistd;
            try {
                if (filePath.isFile && access(toStringz(filePath), X_OK) == 0) {
                    return buildNormalizedPath(filePath);
                } else {
                    return null;
                }
            }
            catch(Exception e) {
                return null;
            }
        }
        
        static string findExecutable(string name) nothrow {
            if (name.isAbsolute()) {
                return checkExecutable(name);
            } else {
                string toReturn;
                try {
                    foreach(path; std.algorithm.splitter(environment.get("PATH"), ':')) {
                        toReturn = checkExecutable(buildPath(path, name));
                        if (toReturn.length) {
                            return toReturn;
                        }
                    }
                } catch(Exception e) {
                    
                }
                return null;
            }
        }
        
        string term = findExecutable("x-terminal-emulator");
        if (!term.empty) {
            return [term, "-e"];
        }
        term = findExecutable("xdg-terminal");
        if (!term.empty) {
            return [term];
        }
        return ["xterm", "-e"];
    } else {
        return null;
    }
}

package void xdgOpen(string url)
{
    spawnProcess(["xdg-open", url], null, Config.none);
}

/**
 * Options to pass to shootDesktopFile.
 * See_Also: shootDesktopFile
 */
struct ShootOptions
{
    /**
     * Flags that changes behavior of shootDesktopFile.
     */
    enum
    {
        Exec = 1, /// shootDesktopFile can start applications.
        Link = 2, /// shootDesktopFile can open links (urls or file names).
        FollowLink = 4, /// If desktop file is link and url points to another desktop file shootDesktopFile will be called on this url with the same options.
        All = Exec|Link|FollowLink /// All flags described above.
    }
    
    /**
     * Flags
     * By default is set to use all flags.
     */
    auto flags = All;
    
    /**
     * Urls to pass to the program is desktop file points to application.
     * Empty by default.
     */
    string[] urls;
    
    /**
     * Locale of environment.
     * Empty by default.
     */
    string locale;
    
    /**
     * Delegate that should be used to open url if desktop file is link.
     * To set static function use std.functional.toDelegate.
     * If it's null shootDesktopFile will use xdg-open.
     */
    void delegate(string) opener = null;
    
    /**
     * Delegate that should be used to get terminal command.
     * To set static function use std.functional.toDelegate.
     * If it's null, shootDesktopFile will use getTerminalCommand.
     * See_Also: getTerminalCommand
     */
    const(string)[] delegate() terminalDetector = null;
}

/**
 * Read the desktop file and run application or open link depending on the type of the given desktop file.
 * Params:
 *  reader = IniLikeReader constructed from range of strings using iniLikeRangeReader
 *  fileName = file name of desktop file where data read from. It's optional, but can be set to the file name from which contents IniLikeReader was constructed.
 *  options = options that set behavior of the function.
 * Use this function to execute desktop file fast, without creating of DesktopFile instance.
 * Throws:
 *  ProcessException on failure to start the process.
 *  DesktopExecException if exec string is invalid.
 *  Exception on other errors.
 * See_Also: ShootOptions
 */
@trusted void shootDesktopFile(IniLikeReader)(IniLikeReader reader, string fileName = null, ShootOptions options = ShootOptions.init)
{
    enforce(options.flags & (ShootOptions.Exec|ShootOptions.Link), "At least one of the options Exec or Link must be provided");
    
    string iconName, name, execString, url, workingDirectory;
    bool terminal;
    
    string bestLocale;
    
    foreach(g; reader.byGroup) {
        if (g.name == "Desktop Entry") {
            foreach(e; g.byEntry) {
                auto t = parseKeyValue(e);
                
                string key = t[0];
                string value = t[1];
                
                if (key.length) {
                    switch(key) {
                        case "Exec": execString = value; break;
                        case "URL": url = value; break;
                        case "Icon": iconName = value; break;
                        case "Path": workingDirectory = value; break;
                        case "Terminal": terminal = isTrue(value); break;
                        default: {
                            auto kl = separateFromLocale(key);
                            if (kl[0] == "Name") {
                                auto lv = chooseLocalizedValue(options.locale, kl[1], value, bestLocale, name);
                                bestLocale = lv[0];
                                name = lv[1];
                            }
                        }
                        break;
                    }
                }
            }
            
            import std.functional : toDelegate;
            
            if (execString.length && (options.flags & ShootOptions.Exec)) {
                auto args = expandExecString(execString, options.urls, iconName, name, fileName);
                
                if (terminal) {
                    if (options.terminalDetector == null) {
                        options.terminalDetector = toDelegate(&getTerminalCommand);
                    }
                    args = options.terminalDetector() ~ args;
                }
                
                execProcess(args, workingDirectory);
            } else if (url.length && (options.flags & ShootOptions.FollowLink) && url.extension == ".desktop" && url.exists) {
                options.flags = options.flags & (~ShootOptions.FollowLink); //avoid recursion
                shootDesktopFile(url, options);
            } else if (url.length && (options.flags & ShootOptions.Link)) {
                if (options.opener == null) {
                    options.opener = toDelegate(&xdgOpen);
                }
                options.opener(url);
            } else {
                if (execString.length) {
                    throw new Exception("Desktop file is an application, but flags don't include ShootOptions.Exec");
                }
                if (url.length) {
                    throw new Exception("Desktop file is a link, but flags don't include ShootOptions.Link");
                }
                throw new Exception("Desktop file is neither application nor link");
            }
            
            return;
        }
    }
    
    throw new Exception("File does not have Desktop Entry group");
}

///
unittest
{
    string contents;
    ShootOptions options;
    
    contents = "[Desktop Entry]\nURL=testurl";
    options.flags = ShootOptions.FollowLink;
    assertThrown(shootDesktopFile(iniLikeStringReader(contents), null, options));
    
    contents = "[Group]\nKey=Value";
    options = ShootOptions.init;
    assertThrown(shootDesktopFile(iniLikeStringReader(contents), null, options));
    
    contents = "[Desktop Entry]\nURL=testurl";
    options = ShootOptions.init;
    bool wasCalled;
    options.opener = delegate void (string url) {
        assert(url == "testurl");
        wasCalled = true;
    };
    
    shootDesktopFile(iniLikeStringReader(contents), null, options);
    assert(wasCalled);
    
    contents = "[Desktop Entry]";
    options = ShootOptions.init;
    assertThrown(shootDesktopFile(iniLikeStringReader(contents), null, options));
    
    contents = "[Desktop Entry]\nURL=testurl";
    options.flags = ShootOptions.Exec;
    assertThrown(shootDesktopFile(iniLikeStringReader(contents), null, options));
    
    contents = "[Desktop Entry]\nExec=whoami";
    options.flags = ShootOptions.Link;
    assertThrown(shootDesktopFile(iniLikeStringReader(contents), null, options));
}

/// ditto, but automatically create IniLikeReader from the file.
@trusted void shootDesktopFile(string fileName, ShootOptions options = ShootOptions.init)
{
    shootDesktopFile(iniLikeFileReader(fileName), fileName, options);
}
