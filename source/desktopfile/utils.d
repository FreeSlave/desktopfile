/**
 * Utility functions for reading and executing desktop files.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 https://www.freedesktop.org/wiki/Specifications/desktop-entry-spec/, Desktop Entry Specification)
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
    
    import findexecutable;
    import isfreedesktop;
}

package @trusted File getNullStdin()
{
    version(Posix) {
        auto toReturn = std.stdio.stdin;
        try {
            toReturn = File("/dev/null", "rb");
        } catch(Exception e) {
            
        }
        return toReturn;
    } else {
        return std.stdio.stdin;
    }
}

package @trusted File getNullStdout()
{
    version(Posix) {
        auto toReturn = std.stdio.stdout;
        try {
            toReturn = File("/dev/null", "wb");
        } catch(Exception e) {
            
        }
        return toReturn;
    } else {
        return std.stdio.stdout;
    }
}

package @trusted File getNullStderr()
{
    version(Posix) {
        auto toReturn = std.stdio.stderr;
        try {
            toReturn = File("/dev/null", "wb");
        } catch(Exception e) {
            
        }
        return toReturn;
    } else {
        return std.stdio.stderr;
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
 * Parameters for spawnApplication.
 */
struct SpawnParams
{
    /// Urls to open
    const(string)[] urls;
    
    /// Icon to use in place of %i field code.
    string iconName;
    
    /// Name to use in place of %c field code.
    string displayName;
    
    /// File name to use in place of %k field code.
    string fileName;
    
    /// Working directory of starting process.
    string workingDirectory;
    
    /// Terminal command to prepend to exec arguments.
    const(string)[] terminalCommand;
    
    /// Allow starting multiple instances of application if needed.
    bool allowMultipleInstances = true;
}

private @trusted Pid execProcess(in string[] args, string workingDirectory = null)
{    
    static if( __VERSION__ < 2066 ) {
        return spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.none);
    } else {
        return spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.none, workingDirectory);
    }
}

/**
 * Spawn application with given params.
 * Params:
 *  unquotedArgs = Unescaped unquoted arguments parsed from "Exec" value.
 *  params = Field codes values and other properties to spawn application.
 * Throws:
 *  ProcessException if could not start process.
 *  DesktopExecException if unquotedArgs is empty.
 * See_Also: $(D SpawnParams)
 */
@trusted Pid spawnApplication(const(string)[] unquotedArgs, const SpawnParams params)
{
    if (!unquotedArgs.length) {
        throw new DesktopExecException("No arguments. Missing or empty Exec value");
    }
    
    version(Windows) {
        if (unquotedArgs.length && unquotedArgs[0].baseName == unquotedArgs[0]) {
            unquotedArgs = findExecutable(unquotedArgs[0]) ~ unquotedArgs[1..$];
        }
    }
    
    if (params.terminalCommand) {
        unquotedArgs = params.terminalCommand ~ unquotedArgs;
    }
    
    if (params.urls.length && params.allowMultipleInstances && needMultipleInstances(unquotedArgs)) {
        Pid pid;
        for(size_t i=0; i<params.urls.length; ++i) {
            pid = execProcess(expandExecArgs(unquotedArgs, params.urls[i..i+1], params.iconName, params.displayName, params.fileName), params.workingDirectory);
        }
        return pid;
    } else {
        return execProcess(expandExecArgs(unquotedArgs, params.urls, params.iconName, params.displayName, params.fileName), params.workingDirectory);
    }
}

private @safe bool needQuoting(string arg) nothrow pure
{
    for (size_t i=0; i<arg.length; ++i)
    {
        switch(arg[i]) {
            case ' ':   case '\t':  case '\n':  case '\r':  case '"': 
            case '\\':  case '\'':  case '>':   case '<':   case '~':
            case '|':   case '&':   case ';':   case '$':   case '*': 
            case '?':   case '#':   case '(':   case ')':   case '`':
                return true;
            default:
                break;
        }
    }
    return false;
}

unittest
{
    assert(needQuoting("hello\tworld"));
    assert(needQuoting("hello world"));
    assert(needQuoting("world?"));
    assert(needQuoting("sneaky_stdout_redirect>"));
    assert(needQuoting("sneaky_pipe|"));
    assert(!needQuoting("hello"));
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

private @trusted string escapeQuotedArgument(string value) pure {
    return value.replace("`", "\\`").replace("\\", `\\`).replace("$", `\$`).replace("\"", `\"`);
}

private @trusted string quoteIfNeeded(string value, char quote = '"') pure {
    if (value.needQuoting) {
        return quote ~ value.escapeQuotedArgument() ~ quote;
    }
    return value;
}

unittest
{
    assert(quoteIfNeeded("hello $world") == `"hello \$world"`);
    assert(quoteIfNeeded("hello \"world\"") == `"hello \"world\""`);
    assert(quoteIfNeeded("hello world") == `"hello world"`);
    assert(quoteIfNeeded("hello") == "hello");
}

/**
 * Apply unquoting to Exec value making it into an array of escaped arguments. It automatically performs quote-related unescaping. Read more: [specification](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html).
 * Params:
 *  value = value of Exec key. Must be unescaped by unescapeValue before passing.
 * Throws:
 *  $(D DesktopExecException) if string can't be unquoted (e.g. no pair quote).
 * Note:
 *  Although Desktop Entry Specification says that arguments must be quoted by double quote, for compatibility reasons this implementation also recognizes single quotes.
 */
@trusted auto unquoteExec(string value) pure
{   
    string[] result;
    size_t i;
    
    static string parseQuotedPart(ref size_t i, char delimeter, string value)
    {
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
        return value[start..i].unescapeQuotedArgument();
    }
    
    string append;
    bool wasInQuotes;
    while(i < value.length) {
        if (value[i] == ' ' || value[i] == '\t') {
            if (!wasInQuotes && append.length >= 1 && append[$-1] == '\\') {
                append = append[0..$-1] ~ value[i];
            } else {
                if (append !is null) {
                    result ~= append;
                    append = null;
                }
            }
            wasInQuotes = false;
        } else if (value[i] == '"' || value[i] == '\'') {
            append ~= parseQuotedPart(i, value[i], value);
            wasInQuotes = true;
        } else {
            append ~= value[i];
            wasInQuotes = false;
        }
        i++;
    }
    
    if (append !is null) {
        result ~= append;
    }
    
    return result;
}

///
unittest 
{
    assert(equal(unquoteExec(``), string[].init));
    assert(equal(unquoteExec(`   `), string[].init));
    assert(equal(unquoteExec(`"" "  "`), [``, `  `]));
    
    assert(equal(unquoteExec(`cmd arg1  arg2   arg3   `), [`cmd`, `arg1`, `arg2`, `arg3`]));
    assert(equal(unquoteExec(`"cmd" arg1 arg2  `), [`cmd`, `arg1`, `arg2`]));
    
    assert(equal(unquoteExec(`"quoted cmd"   arg1  "quoted arg"  `), [`quoted cmd`, `arg1`, `quoted arg`]));
    assert(equal(unquoteExec(`"quoted \"cmd\"" arg1 "quoted \"arg\""`), [`quoted "cmd"`, `arg1`, `quoted "arg"`]));
    
    assert(equal(unquoteExec(`"\\\$" `), [`\$`]));
    assert(equal(unquoteExec(`"\\$" `), [`\$`]));
    assert(equal(unquoteExec(`"\$" `), [`$`]));
    assert(equal(unquoteExec(`"$"`), [`$`]));
    
    assert(equal(unquoteExec(`"\\" `), [`\`]));
    assert(equal(unquoteExec(`"\\\\" `), [`\\`]));
    
    assert(equal(unquoteExec(`'quoted cmd' arg`), [`quoted cmd`, `arg`]));
    
    assert(equal(unquoteExec(`test\ "one""two"\ more\ \ test `), [`test onetwo more  test`]));
    
    assert(equal(unquoteExec(`env WINEPREFIX="/home/freeslave/.wine" wine C:\\windows\\command\\start.exe /Unix /home/freeslave/.wine/dosdevices/c:/windows/profiles/freeslave/Start\ Menu/Programs/True\ Remembrance/True\ Remembrance.lnk`), [
        "env", "WINEPREFIX=/home/freeslave/.wine", "wine", `C:\\windows\\command\\start.exe`, "/Unix", "/home/freeslave/.wine/dosdevices/c:/windows/profiles/freeslave/Start Menu/Programs/True Remembrance/True Remembrance.lnk"
    ]));
    
    assertThrown!DesktopExecException(unquoteExec(`cmd "quoted arg`));
}

private @trusted string urlToFilePath(string url) nothrow pure
{
    enum protocol = "file://";
    if (url.length > protocol.length && url[0..protocol.length] == protocol) {
        return url[protocol.length..$];
    } else {
        return url;
    }
}

/**
 * Expand Exec arguments (usually returned by unquoteExec) replacing field codes with given values, making the array suitable for passing to spawnProcess. Deprecated field codes are ignored.
 * Note:
 *  Returned array may be empty and should be checked before passing to spawnProcess.
 * Params:
 *  unquotedArgs = Array of unescaped and unquoted arguments.
 *  urls = Array of urls or file names that inserted in the place of %f, %F, %u or %U field codes. 
 *      For %f and %u only the first element of array is used.
 *      For %f and %F every url started with 'file://' will be replaced with normal path.
 *  iconName = Icon name used to substitute %i field code by --icon iconName.
 *  displayName = Name of application used that inserted in the place of %c field code.
 *  fileName = Name of desktop file that inserted in the place of %k field code.
 * Throws:
 *  $(D DesktopExecException) if command line contains unknown field code.
 * See_Also: $(D unquoteExec)
 */
@trusted string[] expandExecArgs(in string[] unquotedArgs, in string[] urls = null, string iconName = null, string displayName = null, string fileName = null) pure
{
    string[] toReturn;
    foreach(token; unquotedArgs) {
        if (token == "%F") {
            toReturn ~= urls.map!(url => urlToFilePath(url)).array;
        } else if (token == "%U") {
            toReturn ~= urls;
        } else if (token == "%i") {
            if (iconName.length) {
                toReturn ~= "--icon";
                toReturn ~= iconName;
            }
        } else {
            static void expand(string token, ref string expanded, ref size_t restPos, ref size_t i, string insert)
            {
                if (token.length == 2) {
                    expanded = insert;
                } else {
                    expanded ~= token[restPos..i] ~ insert;
                }
                restPos = i+2;
                i++;
            }
            
            string expanded;
            size_t restPos = 0;
            bool ignore;
            loop: for(size_t i=0; i<token.length; ++i) {
                if (token[i] == '%' && i<token.length-1) {
                    switch(token[i+1]) {
                        case 'f': case 'u':
                        {
                            if (urls.length) {
                                string arg = urls.front;
                                if (token[i+1] == 'f') {
                                    arg = urlToFilePath(arg);
                                }
                                expand(token, expanded, restPos, i, arg);
                            } else {
                                ignore = true;
                                break loop;
                            }
                        }
                        break;
                        case 'c':
                        {
                            expand(token, expanded, restPos, i, displayName);
                        }
                        break;
                        case 'k':
                        {
                            expand(token, expanded, restPos, i, fileName);
                        }
                        break;
                        case 'd': case 'D': case 'n': case 'N': case 'm': case 'v':
                        {
                            ignore = true;
                            break loop;
                        }
                        case '%':
                        {
                            expand(token, expanded, restPos, i, "%");
                        }
                        break;
                        default:
                        {
                            throw new DesktopExecException("Unknown or misplaced field code: " ~ token);
                        }
                    }
                }
            }
            
            if (!ignore) {
                toReturn ~= expanded ~ token[restPos..$];
            }
        }
    }
    
    return toReturn;
}

///
unittest
{
    assert(expandExecArgs(
        ["program path", "%%f", "%%i", "%D", "--deprecated=%d", "%n", "%N", "%m", "%v", "--file=%f", "%i", "%F", "--myname=%c", "--mylocation=%k", "100%%"], 
        ["one"], 
        "folder", "program", "location"
    ) == ["program path", "%f", "%i", "--file=one", "--icon", "folder", "one", "--myname=program", "--mylocation=location", "100%"]);
    
    assert(expandExecArgs(["program path", "many%%%%"]) == ["program path", "many%%"]);
    assert(expandExecArgs(["program path", "%f"]) == ["program path"]);
    assert(expandExecArgs(["program path", "%f%%%f"], ["file"]) == ["program path", "file%file"]);
    assert(expandExecArgs(["program path", "%f"], ["file:///usr/share"]) == ["program path", "/usr/share"]);
    assert(expandExecArgs(["program path", "%u"], ["file:///usr/share"]) == ["program path", "file:///usr/share"]);
    assert(expandExecArgs(["program path"], ["one", "two"]) == ["program path"]);
    assert(expandExecArgs(["program path", "%f"], ["one", "two"]) == ["program path", "one"]);
    assert(expandExecArgs(["program path", "%F"], ["one", "two"]) == ["program path", "one", "two"]);
    assert(expandExecArgs(["program path", "%F"], ["file://one", "file://two"]) == ["program path", "one", "two"]);
    assert(expandExecArgs(["program path", "%U"], ["file://one", "file://two"]) == ["program path", "file://one", "file://two"]);
    
    assert(expandExecArgs(["program path", "--location=%k", "--myname=%c"]) == ["program path", "--location=", "--myname="]);
    assert(expandExecArgs(["program path", "%k", "%c"]) == ["program path", "", ""]);
    assertThrown!DesktopExecException(expandExecArgs(["program name", "%y"]));
    assertThrown!DesktopExecException(expandExecArgs(["program name", "--file=%x"]));
    assertThrown!DesktopExecException(expandExecArgs(["program name", "--files=%F"]));
}

/**
 * Check if application should be started multiple times to open multiple urls.
 * Params:
 *  execArgs = Array of unescaped and unquoted arguments.
 * Returns: true if execArgs have only %f or %u and not %F or %U,. Otherwise false is returned.
 */
@nogc @trusted bool needMultipleInstances(in string[] execArgs) pure nothrow
{
    bool need;
    foreach(token; execArgs) {
        if (token == "%F" || token == "%U") {
            return false;
        }
        
        if (!need) {
            for(size_t i=0; i<token.length; ++i) {
                if (token[i] == '%' && i<token.length-1) {
                    if (token[i+1] == 'f' || token[i+1] == 'u') {
                        need = true;
                    }
                }
            }
        }
    }
    return need;
}

///
unittest
{
    assert(needMultipleInstances(["program", "%f"]));
    assert(needMultipleInstances(["program", "%u"]));
    assert(!needMultipleInstances(["program", "%i"]));
    assert(!needMultipleInstances(["program", "%F"]));
    assert(!needMultipleInstances(["program", "%U"]));
    assert(!needMultipleInstances(["program", "%f", "%U"]));
    assert(!needMultipleInstances(["program", "%F", "%u"]));
}

private @trusted string doublePercentSymbol(string value)
{
    return value.replace("%", "%%");
}

/**
 * Helper struct to build Exec string for desktop file.
 */
struct ExecBuilder
{
    /**
     * Construct ExecBuilder.
     * Params:
     *  executable = path to executable. Value will be escaped and quoted as needed.
     * Throws:
     *  Exception if executable is not absolute path nor base name.
     */
    @safe this(string executable) {
        enforce(executable.isAbsolute || executable.baseName == executable, "Program part of Exec must be absolute path or base name");
        escapedArgs ~= executable.escapeValue().quoteIfNeeded();
    }
    
    /**
     * Add literal argument which is not field code.
     * Params:
     *  arg = Literal argument. Value will be escaped and quoted as needed.
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder argument(string arg) {
        escapedArgs ~= arg.escapeValue().quoteIfNeeded().doublePercentSymbol();
        return this;
    }
    
    /**
     * Add "%i" field code.
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder icon() {
        escapedArgs ~= "%i";
        return this;
    }
    
    
    /**
     * Add "%f" field code.
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder file(string preprend = null) {
        return fieldCode(preprend, "%f");
    }
    
    /**
     * Add "%F" field code.
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder files() {
        escapedArgs ~= "%F";
        return this;
    }
    
    /**
     * Add "%u" field code.
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder url(string preprend = null) {
        return fieldCode(preprend, "%u");
    }
    
    /**
     * Add "%U" field code.
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder urls() {
        escapedArgs ~= "%U";
        return this;
    }
    
    /**
     * Add "%c" field code (name of application).
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder displayName(string preprend = null) {
        return fieldCode(preprend, "%c");
    }
    
    /**
     * Add "%k" field code (location of desktop file).
     * Returns: this object for chained calls.
     */
    @safe ExecBuilder location(string preprend = null) {
        return fieldCode(preprend, "%k");
    }
    
    /**
     * Get resulting string that can be set to Exec field of Desktop Entry.
     */
    @trusted string result() const {
        static if( __VERSION__ < 2066 ) {
            return escapedArgs.map!(s => s).join(" ");
        } else {
            return escapedArgs.join(" ");
        }
    }
    
private:
    @safe ExecBuilder fieldCode(string prepend, string code)
    {
        escapedArgs ~= prepend.doublePercentSymbol() ~ code;
        return this;
    }
    
    string[] escapedArgs;
}

///
unittest
{
    assert(ExecBuilder("quoted program").icon()
            .argument("-w").displayName()
            .argument("$value")
            .argument("slash\\")
            .argument("100%")
            .location("--location=")
            .urls().url().file("--file=").files().result() == `"quoted program" %i -w %c "\$value" "slash\\\\" 100%% --location=%k %U %u --file=%f %F`);
    
    assertThrown(ExecBuilder("./relative/path"));
}

/**
 * Detect command which will run program in terminal emulator.
 * On Freedesktop it looks for x-terminal-emulator first. If found ["/path/to/x-terminal-emulator", "-e"] is returned.
 * Otherwise it looks for xdg-terminal. If found ["/path/to/xdg-terminal"] is returned.
 * Otherwise it tries to detect your desktop environment and find default terminal emulator for it.
 * If all guesses failed, it uses ["xterm", "-e"] as fallback.
 * Note: This function always returns empty array on non-freedesktop systems.
 */
string[] getTerminalCommand() nothrow @trusted 
{
    static if (isFreedesktop) {
        static string getDefaultTerminal() nothrow
        {
            string xdgCurrentDesktop;
            collectException(environment.get("XDG_CURRENT_DESKTOP"), xdgCurrentDesktop);
            switch(xdgCurrentDesktop) {
                case "GNOME":
                case "X-Cinnamon":
                    return "gnome-terminal";
                case "LXDE":
                    return "lxterminal";
                case "XFCE":
                    return "xfce4-terminal";
                case "MATE":
                    return "mate-terminal";
                case "KDE":
                    return "konsole";
                default:
                    return null;
            }
        }
        
        string[] paths;
        collectException(binPaths().array, paths);
        
        string term = findExecutable("x-terminal-emulator", paths);
        if (!term.empty) {
            return [term, "-e"];
        }
        term = findExecutable("xdg-terminal", paths);
        if (!term.empty) {
            return [term];
        }
        term = getDefaultTerminal();
        if (!term.empty) {
            term = findExecutable(term, paths);
            if (!term.empty) {
                return [term, "-e"];
            }
        }
        return ["xterm", "-e"];
    } else {
        return null;
    }
}

unittest
{
    import isfreedesktop;
    static if (isFreedesktop) {
        import desktopfile.paths;
        
        auto pathGuard = EnvGuard("PATH");
        
        try {
            static void changeMod(string fileName, uint mode)
            {
                import core.sys.posix.sys.stat;
                enforce(chmod(fileName.toStringz, cast(mode_t)mode) == 0);
            }
            
            string tempPath = buildPath(tempDir(), "desktopfile-unittest-tempdir");
            
            if (!tempPath.exists) {
                mkdir(tempPath);
            }
            scope(exit) rmdir(tempPath);
            
            environment["PATH"] = tempPath;
            
            string tempXTerminalEmulatorFile = buildPath(tempPath, "x-terminal-emulator");
            string tempXdgTerminalFile = buildPath(tempPath, "xdg-terminal");
            
            File(tempXdgTerminalFile, "w");
            scope(exit) remove(tempXdgTerminalFile);
            changeMod(tempXdgTerminalFile, octal!755);
            enforce(getTerminalCommand() == [buildPath(tempPath, "xdg-terminal")]);
            
            changeMod(tempXdgTerminalFile, octal!644);
            enforce(getTerminalCommand() == ["xterm", "-e"]);
            
            File(tempXTerminalEmulatorFile, "w");
            scope(exit) remove(tempXTerminalEmulatorFile);
            changeMod(tempXTerminalEmulatorFile, octal!755);
            enforce(getTerminalCommand() == [buildPath(tempPath, "x-terminal-emulator"), "-e"]);
            
            environment["PATH"] = ":";
            enforce(getTerminalCommand() == ["xterm", "-e"]);
            
        } catch(Exception e) {
            
        }
    } else {
        assert(getTerminalCommand().empty);
    }
}

package void xdgOpen(string url)
{
    spawnProcess(["xdg-open", url], getNullStdin(), getNullStdout(), getNullStderr());
}

/**
 * Options to pass to shootDesktopFile.
 * See_Also: $(D shootDesktopFile)
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
    const(string)[] urls;
    
    /**
     * Locale of environment.
     * Empty by default.
     */
    string locale;
    
    /**
     * Delegate that will be used to open url if desktop file is link.
     * To set static function use std.functional.toDelegate.
     * If it's null shootDesktopFile will use xdg-open.
     */
    void delegate(string) opener = null;
    
    /**
     * Delegate that will be used to get terminal command if desktop file is application and needs to ran in terminal.
     * To set static function use std.functional.toDelegate.
     * If it's null, shootDesktopFile will use getTerminalCommand.
     * See_Also: $(D getTerminalCommand)
     */
    const(string)[] delegate() terminalDetector = null;
    
    /**
     * Allow to run multiple instances of application if it does not support opening multiple urls in one instance.
     */
    bool allowMultipleInstances = true;
}

package void readNeededKeys(Group)(Group g, string locale, 
                            out string iconName, out string name, 
                            out string execValue, out string url, 
                            out string workingDirectory, out bool terminal)
{
    string bestLocale;
    foreach(e; g.byEntry) {
        auto t = parseKeyValue(e);
        
        string key = t[0];
        string value = t[1];
        
        if (key.length) {
            switch(key) {
                case "Exec": execValue = value.unescapeValue(); break;
                case "URL": url = value.unescapeValue(); break;
                case "Icon": iconName = value.unescapeValue(); break;
                case "Path": workingDirectory = value.unescapeValue(); break;
                case "Terminal": terminal = isTrue(value); break;
                default: {
                    auto kl = separateFromLocale(key);
                    if (kl[0] == "Name") {
                        auto lv = chooseLocalizedValue(locale, kl[1], value, bestLocale, name);
                        bestLocale = lv[0];
                        name = lv[1].unescapeValue();
                    }
                }
                break;
            }
        }
    }
}

unittest
{
    string contents = "[Desktop Entry]\nExec=whoami\nURL=http://example.org\nIcon=folder\nPath=/usr/bin\nTerminal=true\nName=Example\nName[ru]=Пример";
    auto reader = iniLikeStringReader(contents);
    
    string iconName, name, execValue, url, workingDirectory;
    bool terminal;
    readNeededKeys(reader.byGroup().front, "ru_RU", iconName, name , execValue, url, workingDirectory, terminal);
    assert(iconName == "folder");
    assert(execValue == "whoami");
    assert(url == "http://example.org");
    assert(workingDirectory == "/usr/bin");
    assert(terminal);
    assert(name == "Пример");
}

/**
 * Read the desktop file and run application or open link depending on the type of the given desktop file.
 * Params:
 *  reader = IniLikeReader constructed from range of strings using iniLikeRangeReader
 *  fileName = file name of desktop file where data read from. Can be used in field code expanding, should be set to the file name from which contents IniLikeReader was constructed.
 *  options = options that set behavior of the function.
 * Use this function to execute desktop file fast, without creating of DesktopFile instance.
 * Throws:
 *  ProcessException on failure to start the process.
 *  $(D DesktopExecException) if exec string is invalid.
 *  Exception on other errors.
 * See_Also: $(D ShootOptions)
 */
void shootDesktopFile(IniLikeReader)(IniLikeReader reader, string fileName = null, ShootOptions options = ShootOptions.init)
{
    enforce(options.flags & (ShootOptions.Exec|ShootOptions.Link), "At least one of the options Exec or Link must be provided");
    
    string iconName, name, execValue, url, workingDirectory;
    bool terminal;
    
    foreach(g; reader.byGroup) {
        if (g.groupName == "Desktop Entry") {
            readNeededKeys(g, options.locale, iconName, name, execValue, url, workingDirectory, terminal);
            
            import std.functional : toDelegate;
            
            if (execValue.length && (options.flags & ShootOptions.Exec)) {
                auto unquotedArgs = unquoteExec(execValue);
                
                SpawnParams params;
                params.urls = options.urls;
                params.iconName = iconName;
                params.displayName = name;
                params.fileName = fileName;
                params.workingDirectory = workingDirectory;
                
                if (terminal) {
                    if (options.terminalDetector == null) {
                        options.terminalDetector = toDelegate(&getTerminalCommand);
                    }
                    params.terminalCommand = options.terminalDetector();
                }
                spawnApplication(unquotedArgs, params);
            } else if (url.length && (options.flags & ShootOptions.FollowLink) && url.extension == ".desktop" && url.exists) {
                options.flags = options.flags & (~ShootOptions.FollowLink); //avoid recursion
                shootDesktopFile(url, options);
            } else if (url.length && (options.flags & ShootOptions.Link)) {
                if (options.opener == null) {
                    options.opener = toDelegate(&xdgOpen);
                }
                options.opener(url);
            } else {
                if (execValue.length) {
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
    
    static if (isFreedesktop) {
        try {
            contents = "[Desktop Entry]\nExec=whoami\nTerminal=true";
            options.flags = ShootOptions.Exec;
            wasCalled = false;
            options.terminalDetector = delegate string[] () {wasCalled = true; return null;};
            shootDesktopFile(iniLikeStringReader(contents), null, options);
            assert(wasCalled);
            
            string tempPath = buildPath(tempDir(), "desktopfile-unittest-tempdir");
            if (!tempPath.exists) {
                mkdir(tempPath);
            }
            scope(exit) rmdir(tempPath);
            
            string tempDesktopFile = buildPath(tempPath, "followtest.desktop");
            auto f = File(tempDesktopFile, "w");
            scope(exit) remove(tempDesktopFile);
            f.rawWrite("[Desktop Entry]\nURL=testurl");
            f.flush();
            
            contents = "[Desktop Entry]\nURL=" ~ tempDesktopFile;
            options.flags = ShootOptions.Link | ShootOptions.FollowLink;
            options.opener = delegate void (string url) {
                assert(url == "testurl");
                wasCalled = true;
            };
            
            shootDesktopFile(iniLikeStringReader(contents), null, options);
            assert(wasCalled);
        } catch(Exception e) {
            
        }
    }
    
    
}

/// ditto, but automatically create IniLikeReader from the file.
@trusted void shootDesktopFile(string fileName, ShootOptions options = ShootOptions.init)
{
    shootDesktopFile(iniLikeFileReader(fileName), fileName, options);
}

/**
 * See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID)
 * Params: 
 *  fileName = Desktop file.
 *  appsPaths = Range of base application paths.
 * Returns: Desktop file ID or empty string if file does not have an ID.
 * See_Also: $(D desktopfile.paths.applicationsPaths)
 */
string desktopId(Range)(string fileName, Range appsPaths) if (isInputRange!Range && is(ElementType!Range : string))
{
    try {
        string absolute = fileName.absolutePath;
        foreach (path; appsPaths) {
            auto pathSplit = pathSplitter(path);
            auto fileSplit = pathSplitter(absolute);
            
            while (!pathSplit.empty && !fileSplit.empty && pathSplit.front == fileSplit.front) {
                pathSplit.popFront();
                fileSplit.popFront();
            }
            
            if (pathSplit.empty) {
                static if( __VERSION__ < 2066 ) {
                    return to!string(fileSplit.map!(s => to!string(s)).join("-"));
                } else {
                    return to!string(fileSplit.join("-"));
                }
            }
        }
    } catch(Exception e) {
        
    }
    return null;
}

///
unittest
{
    string[] appPaths;
    string filePath, nestedFilePath, wrongFilePath;
    
    version(Windows) {
        appPaths = [`C:\ProgramData\KDE\share\applications`, `C:\Users\username\.kde\share\applications`];
        filePath = `C:\ProgramData\KDE\share\applications\example.desktop`;
        nestedFilePath = `C:\ProgramData\KDE\share\applications\kde\example.desktop`;
        wrongFilePath = `C:\ProgramData\desktop\example.desktop`;
    } else {
        appPaths = ["/usr/share/applications", "/usr/local/share/applications"];
        filePath = "/usr/share/applications/example.desktop";
        nestedFilePath = "/usr/share/applications/kde/example.desktop";
        wrongFilePath = "/etc/desktop/example.desktop";
    }
    
    assert(desktopId(nestedFilePath, appPaths) == "kde-example.desktop");
    assert(desktopId(filePath, appPaths) == "example.desktop");
    assert(desktopId(wrongFilePath, appPaths).empty);
    assert(desktopId("", appPaths).empty);
}

static if (isFreedesktop)
{
    /** 
     * See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html, Desktop File ID)
     * Returns: Desktop file ID or empty string if file does not have an ID.
     * Params:
     *  fileName = Desktop file.
     * Note: This function retrieves applications paths each time it's called and therefore can impact performance. To avoid this issue use the overload with argument.
     * See_Also: $(D desktopfile.paths.applicationsPaths)
     */
    @trusted string desktopId(string fileName) nothrow
    {
        import desktopfile.paths;
        return desktopId(fileName, applicationsPaths());
    }
}

/**
 * Find desktop file by Desktop File ID.
 * Desktop file ID can be ambiguous when it has hyphen symbol, so this function can try both variants.
 * Params:
 *  desktopId = Desktop file ID.
 *  appsPaths = Range of base application paths.
 * Returns: The first found existing desktop file, or null if could not find any.
 * Note: This does not ensure that file is valid .desktop file.
 * See_Also: $(D desktopfile.paths.applicationsPaths)
 */
string findDesktopFile(Range)(string desktopId, Range appsPaths) if (isInputRange!Range && is(ElementType!Range : string))
{
    if (desktopId != desktopId.baseName) {
        return null;
    }
    
    foreach(appsPath; appsPaths) {
        auto filePath = buildPath(appsPath, desktopId);
        bool fileExists = filePath.exists;
        if (!fileExists && filePath.canFind('-')) {
            filePath = buildPath(appsPath, desktopId.replace("-", "/"));
            fileExists = filePath.exists;
        }
        if (fileExists) {
            return filePath;
        }
    }
    return null;
}

///
unittest
{
    assert(findDesktopFile("not base/path.desktop", ["/usr/share/applications"]) is null);
    assert(findDesktopFile("valid.desktop", (string[]).init) is null);
}

static if (isFreedesktop) 
{
    /**
     * ditto
     * Note: This function retrieves applications paths each time it's called and therefore can impact performance. To avoid this issue use the overload with argument.
     * See_Also: $(D desktopfile.paths.applicationsPaths)
     */
    @trusted string findDesktopFile(string desktopId) nothrow
    {
        import desktopfile.paths;
        try {
            return findDesktopFile(desktopId, applicationsPaths());
        } catch(Exception e) {
            return null;
        }
    }
}

/**
 * Check if .desktop file is trusted. This is not actually part of Desktop File Specification but many file managers has this concept.
 * The trusted .desktop file is a file the current user has executable access to or the owner of which is root.
 * This function should be applicable only to desktop files of Application type.
 * Note: Always returns true on non-posix systems.
 */
@trusted bool isTrusted(string appFileName) nothrow
{
    version(Posix) {
        import core.sys.posix.sys.stat;
        import core.sys.posix.unistd;
        
        try { // try for outdated compilers
            auto namez = toStringz(appFileName);
            if (access(namez, X_OK) == 0) {
                return true;
            }
            
            stat_t statbuf;
            auto result = stat(namez, &statbuf);
            return (result == 0 && statbuf.st_uid == 0);
        } catch(Exception e) {
            return false;
        }
    } else {
        return true;
    }
}
