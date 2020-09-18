/**
 * Utility functions for reading and executing desktop files.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
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
 * Parameters for $(D spawnApplication).
 */
struct SpawnParams
{
    /// Urls or file paths to open
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

private @trusted void execProcess(scope const(string)[] args, string workingDirectory = null)
{
    spawnProcess(args, getNullStdin(), getNullStdout(), getNullStderr(), null, Config.detached, workingDirectory);
}

/**
 * Spawn application with given params.
 * Params:
 *  unquotedArgs = Unescaped unquoted arguments parsed from "Exec" value.
 *  params = Field codes values and other properties to spawn application.
 * Throws:
 *  $(B ProcessException) if could not start process.
 *  $(D DesktopExecException) if unquotedArgs is empty.
 * See_Also: $(D SpawnParams)
 */
@trusted void spawnApplication(const(string)[] unquotedArgs, const SpawnParams params)
{
    if (!unquotedArgs.length) {
        throw new DesktopExecException("No arguments. Missing or empty Exec value");
    }

    if (params.terminalCommand) {
        unquotedArgs = params.terminalCommand ~ unquotedArgs;
    }

    if (params.urls.length && params.allowMultipleInstances && needMultipleInstances(unquotedArgs)) {
        for(size_t i=0; i<params.urls.length; ++i) {
            execProcess(expandExecArgs(unquotedArgs, params.urls[i..i+1], params.iconName, params.displayName, params.fileName), params.workingDirectory);
        }
    } else {
        return execProcess(expandExecArgs(unquotedArgs, params.urls, params.iconName, params.displayName, params.fileName), params.workingDirectory);
    }
}

private @safe bool needQuoting(char c) nothrow pure
{
    switch(c) {
        case ' ':   case '\t':  case '\n':  case '\r':  case '"':
        case '\\':  case '\'':  case '>':   case '<':   case '~':
        case '|':   case '&':   case ';':   case '$':   case '*':
        case '?':   case '#':   case '(':   case ')':   case '`':
            return true;
        default:
            return false;
    }
}

private @safe bool needQuoting(scope string arg) nothrow pure
{
    if (arg.length == 0) {
        return true;
    }

    for (size_t i=0; i<arg.length; ++i)
    {
        if (needQuoting(arg[i])) {
            return true;
        }
    }
    return false;
}

unittest
{
    assert(needQuoting(""));
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

/**
 * Apply unquoting to Exec value making it into an array of escaped arguments. It automatically performs quote-related unescaping.
 * Params:
 *  unescapedValue = value of Exec key. Must be unescaped by $(D unescapeValue) before passing (general escape rule is not the same as quote escape rule).
 * Throws:
 *  $(D DesktopExecException) if string can't be unquoted (e.g. no pair quote).
 * Note:
 *  Although Desktop Entry Specification says that arguments must be quoted by double quote, for compatibility reasons this implementation also recognizes single quotes.
 * See_Also:
 *  $(LINK2 https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s07.html, specification)
 */
@trusted auto unquoteExec(string unescapedValue) pure
{
    auto value = unescapedValue;
    string[] result;
    size_t i;

    static string parseQuotedPart(ref size_t i, char delimeter, string value)
    {
        const size_t start = ++i;

        while(i < value.length) {
            if (value[i] == '\\' && value.length > i+1) {
                const char next = value[i+1];
                if (next == '\\' || next  == delimeter) {
                    i+=2;
                    continue;
                }
            }

            if (value[i] == delimeter) {
                return value[start..i].unescapeQuotedArgument();
            }
            ++i;
        }
        throw new DesktopExecException("Missing pair quote");
    }

    char[] append;
    while(i < value.length) {
        if (value[i] == '\\' && i+1 < value.length && needQuoting(value[i+1])) {
            // this is actually does not adhere to the spec, but we need it to support some wine-generated .desktop files
            append ~= value[i+1];
            ++i;
        } else if (value[i] == ' ' || value[i] == '\t') {
            if (append !is null) {
                result ~= append.assumeUnique;
                append = null;
            }
        } else if (value[i] == '"' || value[i] == '\'') {
            // some DEs can produce files with quoting by single quotes when there's a space in path
            // it's not actually part of the spec, but we support it
            append ~= parseQuotedPart(i, value[i], value);
        } else {
            append ~= value[i];
        }
        ++i;
    }

    if (append !is null) {
        result ~= append.assumeUnique;
    }

    return result;
}

///
unittest
{
    assert(equal(unquoteExec(``), string[].init));
    assert(equal(unquoteExec(`   `), string[].init));
    assert(equal(unquoteExec(`""`), [``]));
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

    assert(equal(unquoteExec(`test\ \ testing`), [`test  testing`]));
    assert(equal(unquoteExec(`test\  testing`), [`test `, `testing`]));
    assert(equal(unquoteExec(`test\ "one""two"\ more\ \ test `), [`test onetwo more  test`]));
    assert(equal(unquoteExec(`"one"two"three"`), [`onetwothree`]));

    assert(equal(unquoteExec(`env WINEPREFIX="/home/freeslave/.wine" wine C:\\windows\\command\\start.exe /Unix /home/freeslave/.wine/dosdevices/c:/windows/profiles/freeslave/Start\ Menu/Programs/True\ Remembrance/True\ Remembrance.lnk`), [
        "env", "WINEPREFIX=/home/freeslave/.wine", "wine", `C:\windows\command\start.exe`, "/Unix", "/home/freeslave/.wine/dosdevices/c:/windows/profiles/freeslave/Start Menu/Programs/True Remembrance/True Remembrance.lnk"
    ]));
    assert(equal(unquoteExec(`Sister\'s\ book\(TM\)`), [`Sister's book(TM)`]));

    assertThrown!DesktopExecException(unquoteExec(`cmd "quoted arg`));
    assertThrown!DesktopExecException(unquoteExec(`"`));
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
 * Expand Exec arguments (usually returned by $(D unquoteExec)) replacing field codes with given values, making the array suitable for passing to spawnProcess.
 * Deprecated field codes are ignored.
 * Note:
 *  Returned array may be empty and must be checked before passing to spawning the process.
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
@trusted string[] expandExecArgs(scope const(string)[] unquotedArgs, scope const(string)[] urls = null, string iconName = null, string displayName = null, string fileName = null) pure
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
 * Flag set of parameter kinds supported by application.
 * Having more than one flag means that Exec command is ambiguous.
 * See_Also: $(D paramSupport)
 */
enum ParamSupport
{
    /**
     * Application does not support parameters.
     */
    none = 0,

    /**
     * Application can open single file at once.
     */
    file = 1,
    /**
     * Application can open multiple files at once.
     */
    files = 2,
    /**
     * Application understands URL syntax and can open single link at once.
     */
    url = 4,
    /**
     * Application supports URL syntax and can open multiple links at once.
     */
    urls = 8
}

/**
 * Evaluate ParamSupport flags for application Exec command.
 * Params:
 *  execArgs = Array of unescaped and unquoted arguments.
 * See_Also: $(D unquoteExec), $(D needMultipleInstances)
 */
@nogc @safe ParamSupport paramSupport(scope const(string)[] execArgs) pure nothrow
{
    auto support = ParamSupport.none;
    foreach(token; execArgs) {
        if (token == "%F") {
            support |= ParamSupport.files;
        } else if (token == "%U") {
            support |= ParamSupport.urls;
        } else if (!(support & (ParamSupport.file | ParamSupport.url))) {
            for(size_t i=0; i<token.length; ++i) {
                if (token[i] == '%' && i<token.length-1) {
                    if (token[i+1] == '%') {
                        i++;
                    } else if (token[i+1] == 'f') {
                        support |= ParamSupport.file;
                        i++;
                    } else if (token[i+1] == 'u') {
                        support |= ParamSupport.url;
                        i++;
                    }
                }
            }
        }
    }
    return support;
}

///
unittest
{
    assert(paramSupport(["program", "%f"]) == ParamSupport.file);
    assert(paramSupport(["program", "%%f"]) == ParamSupport.none);
    assert(paramSupport(["program", "%%%f"]) == ParamSupport.file);
    assert(paramSupport(["program", "%u"]) == ParamSupport.url);
    assert(paramSupport(["program", "%i"]) == ParamSupport.none);
    assert(paramSupport(["program", "%u%f"]) == (ParamSupport.url | ParamSupport.file ));
    assert(paramSupport(["program", "%F"]) == ParamSupport.files);
    assert(paramSupport(["program", "%U"]) == ParamSupport.urls);
    assert(paramSupport(["program", "%f", "%U"]) == (ParamSupport.file|ParamSupport.urls));
    assert(paramSupport(["program", "%F", "%u"]) == (ParamSupport.files|ParamSupport.url));
}

/**
 * Check if application should be started multiple times to open multiple urls.
 * Params:
 *  execArgs = Array of unescaped and unquoted arguments.
 * Returns: true if execArgs have only %f or %u and not %F or %U. Otherwise false is returned.
 * See_Also: $(D unquoteExec), $(D paramSupport)
 */
@nogc @safe bool needMultipleInstances(scope const(string)[] execArgs) pure nothrow
{
    auto support = paramSupport(execArgs);
    const bool noNeed = support == ParamSupport.none || (support & (ParamSupport.urls|ParamSupport.files)) != 0;
    return !noNeed;
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

private struct ExecToken
{
    string token;
    bool needQuotes;
}

/**
 * Helper struct to build Exec string for desktop file.
 * Note:
 *  While Desktop Entry Specification says that field codes must not be inside quoted argument,
 *  ExecBuilder does not consider it as error and may create quoted argument if field code is prepended by the string that needs quotation.
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
        execTokens ~= ExecToken(executable, executable.needQuoting());
    }

    /**
     * Add literal argument which is not field code.
     * Params:
     *  arg = Literal argument. Value will be escaped and quoted as needed.
     *  forceQuoting = Whether to force argument quotation.
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder argument(string arg, Flag!"forceQuoting" forceQuoting = No.forceQuoting) return {
        execTokens ~= ExecToken(arg.doublePercentSymbol(), arg.needQuoting() || forceQuoting);
        return this;
    }

    /**
     * Add "%i" field code.
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder icon() return {
        execTokens ~= ExecToken("%i", false);
        return this;
    }


    /**
     * Add "%f" field code.
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder file(string prepend = null) return {
        return fieldCode(prepend, "%f");
    }

    /**
     * Add "%F" field code.
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder files() return {
        execTokens ~= ExecToken("%F");
        return this;
    }

    /**
     * Add "%u" field code.
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder url(string prepend = null) return {
        return fieldCode(prepend, "%u");
    }

    /**
     * Add "%U" field code.
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder urls() return {
        execTokens ~= ExecToken("%U");
        return this;
    }

    /**
     * Add "%c" field code (name of application).
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder displayName(string prepend = null) return {
        return fieldCode(prepend, "%c");
    }

    /**
     * Add "%k" field code (location of desktop file).
     * Returns: this object for chained calls.
     */
    @safe ref ExecBuilder location(string prepend = null) return {
        return fieldCode(prepend, "%k");
    }

    /**
     * Get resulting string that can be set to Exec field of Desktop Entry. The returned string is escaped.
     */
    @trusted string result() const {
        return execTokens.map!(t => (t.needQuotes ? ('"' ~ t.token.escapeQuotedArgument() ~ '"') : t.token)).join(" ").escapeValue();
    }

private:
    @safe ref ExecBuilder fieldCode(string prepend, string code) return
    {
        string token = prepend.doublePercentSymbol() ~ code;
        execTokens ~= ExecToken(token, token.needQuoting());
        return this;
    }

    ExecToken[] execTokens;
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
            .urls().url().file("--file=").files().result() == `"quoted program" %i -w %c "\\$value" "slash\\\\" 100%% --location=%k %U %u --file=%f %F`);

    assert(ExecBuilder("program").argument("").url("my url ").result() == `program "" "my url %u"`);

    assertThrown(ExecBuilder("./relative/path"));
}

static if (isFreedesktop)
{
    package string[] getDefaultTerminalCommand() nothrow
    {
        import std.utf : byCodeUnit;
        string xdgCurrentDesktop;
        collectException(environment.get("XDG_CURRENT_DESKTOP"), xdgCurrentDesktop);
        foreach(desktop; xdgCurrentDesktop.byCodeUnit.splitter(':'))
        {
            switch(desktop.source) {
                case "GNOME":
                case "X-Cinnamon":
                case "Cinnamon":
                    return ["gnome-terminal", "-x"];
                case "LXDE":
                    return ["lxterminal", "-e"];
                case "XFCE":
                    return ["xfce4-terminal", "-x"];
                case "MATE":
                    return ["mate-terminal", "-x"];
                case "KDE":
                    return ["konsole", "-e"];
                default:
                    break;
            }
        }
        return null;
    }

    unittest
    {
        import desktopfile.paths : EnvGuard;
        EnvGuard currentDesktopGuard = EnvGuard("XDG_CURRENT_DESKTOP", "KDE");
        assert(getDefaultTerminalCommand()[0] == "konsole");

        environment["XDG_CURRENT_DESKTOP"] = "unity:GNOME";
        assert(getDefaultTerminalCommand()[0] == "gnome-terminal");

        environment["XDG_CURRENT_DESKTOP"] = null;
        assert(getDefaultTerminalCommand().empty);

        environment["XDG_CURRENT_DESKTOP"] = "Generic";
        assert(getDefaultTerminalCommand().empty);
    }
}

/**
 * Detect command which will run program in terminal emulator.
 * It tries to detect your desktop environment and find default terminal emulator for it.
 * If all guesses failed, it uses ["xterm", "-e"] as fallback.
 * Note: This function always returns empty array on non-freedesktop systems.
 */
string[] getTerminalCommand() nothrow @trusted
{
    static if (isFreedesktop) {
        string[] paths;
        collectException(binPaths().array, paths);

        string[] termCommand = getDefaultTerminalCommand();
        if (!termCommand.empty) {
            termCommand[0] = findExecutable(termCommand[0], paths);
            if (termCommand[0] != string.init)
                return termCommand;
        }

        string term = findExecutable("rxvt", paths);
        if (!term.empty)
            return [term, "-e"];

        return ["xterm", "-e"];
    } else {
        return null;
    }
}

///
unittest
{
    if (isFreedesktop)
    {
        import desktopfile.paths : EnvGuard;
        EnvGuard pathGuard = EnvGuard("PATH", ":");
        assert(getTerminalCommand() == ["xterm", "-e"]);
    }
    else
    {
        assert(getTerminalCommand().empty);
    }
}

package void xdgOpen(scope string url)
{
    execProcess(["xdg-open", url]);
}

/**
 * Options to pass to $(D fireDesktopFile).
 */
struct FireOptions
{
    /**
     * Flags that changes behavior of fireDesktopFile.
     */
    enum
    {
        Exec = 1, /// $(D fireDesktopFile) can start applications.
        Link = 2, /// $(D fireDesktopFile) can open links (urls or file names).
        FollowLink = 4, /// If desktop file is link and url points to another desktop file fireDesktopFile will be called on this url with the same options.
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
     * If it's null fireDesktopFile will use xdg-open.
     */
    void delegate(string) opener = null;

    /**
     * Delegate that will be used to get terminal command if desktop file is application and needs to ran in terminal.
     * To set static function use std.functional.toDelegate.
     * If it's null, fireDesktopFile will use getTerminalCommand.
     * See_Also: $(D getTerminalCommand)
     */
    const(string)[] delegate() terminalDetector = null;

    /**
     * Allow to run multiple instances of application if it does not support opening multiple urls in one instance.
     */
    bool allowMultipleInstances = true;
}

package bool readDesktopEntryValues(IniLikeReader)(IniLikeReader reader, scope string locale, string fileName,
                            out string iconName, out string name,
                            out string execValue, out string url,
                            out string workingDirectory, out bool terminal)
{
    import inilike.read;
    string bestLocale;
    bool hasDesktopEntry;
    auto onMyGroup = delegate ActionOnGroup(string groupName) {
        if (groupName == "Desktop Entry") {
            hasDesktopEntry = true;
            return ActionOnGroup.stopAfter;
        } else {
            return ActionOnGroup.skip;
        }
    };
    auto onMyKeyValue = delegate void(string key, string value, string groupName) {
        if (groupName != "Desktop Entry") {
            return;
        }
        switch(key) {
            case "Exec": execValue = value.unescapeValue(); break;
            case "URL": url = value.unescapeValue(); break;
            case "Icon": iconName = value.unescapeValue(); break;
            case "Path": workingDirectory = value.unescapeValue(); break;
            case "Terminal": terminal = isTrue(value); break;
            default: {
                auto kl = separateFromLocale(key);
                if (kl[0] == "Name") {
                    auto lv = selectLocalizedValue(locale, kl[1], value, bestLocale, name);
                    bestLocale = lv[0];
                    name = lv[1].unescapeValue();
                }
            }
            break;
        }
    };

    readIniLike(reader, null, onMyGroup, onMyKeyValue, null, fileName);
    return hasDesktopEntry;
}

unittest
{
    string contents = "[Desktop Entry]\nExec=whoami\nURL=http://example.org\nIcon=folder\nPath=/usr/bin\nTerminal=true\nName=Example\nName[ru]=Пример";
    auto reader = iniLikeStringReader(contents);

    string iconName, name, execValue, url, workingDirectory;
    bool terminal;
    readDesktopEntryValues(reader, "ru_RU", null, iconName, name , execValue, url, workingDirectory, terminal);
    assert(iconName == "folder");
    assert(execValue == "whoami");
    assert(url == "http://example.org");
    assert(workingDirectory == "/usr/bin");
    assert(terminal);
    assert(name == "Пример");
    readDesktopEntryValues(reader, string.init, null, iconName, name , execValue, url, workingDirectory, terminal);
    assert(name == "Example");
}

/**
 * Read the desktop file and run application or open link depending on the type of the given desktop file.
 * Params:
 *  reader = $(D inilike.range.IniLikeReader) returned by $(D inilike.range.iniLikeRangeReader) or similar function.
 *  fileName = file name of desktop file where data read from. Can be used in field code expanding, should be set to the file name from which contents $(D inilike.range.IniLikeReader) was constructed.
 *  options = options that set behavior of the function.
 * Use this function to execute desktop file fast, without creating of DesktopFile instance.
 * Throws:
 *  $(B ProcessException) on failure to start the process.
 *  $(D DesktopExecException) if exec string is invalid.
 *  $(B Exception) on other errors.
 * See_Also: $(D FireOptions), $(D spawnApplication), $(D getTerminalCommand)
 */
void fireDesktopFile(IniLikeReader)(IniLikeReader reader, string fileName = null, FireOptions options = FireOptions.init)
{
    enforce(options.flags & (FireOptions.Exec|FireOptions.Link), "At least one of the options Exec or Link must be provided");

    string iconName, name, execValue, url, workingDirectory;
    bool terminal;

    if (readDesktopEntryValues(reader, options.locale, fileName, iconName, name, execValue, url, workingDirectory, terminal)) {
        import std.functional : toDelegate;

        if (execValue.length && (options.flags & FireOptions.Exec)) {
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
        } else if (url.length && (options.flags & FireOptions.FollowLink) && url.extension == ".desktop" && url.exists) {
            options.flags = options.flags & (~FireOptions.FollowLink); //avoid recursion
            fireDesktopFile(url, options);
        } else if (url.length && (options.flags & FireOptions.Link)) {
            if (options.opener == null) {
                options.opener = toDelegate(&xdgOpen);
            }
            options.opener(url);
        } else {
            if (execValue.length) {
                throw new Exception("Desktop file is an application, but flags don't include FireOptions.Exec");
            }
            if (url.length) {
                throw new Exception("Desktop file is a link, but flags don't include FireOptions.Link");
            }
            throw new Exception("Desktop file is neither application nor link");
        }
    } else {
        throw new Exception("File does not have Desktop Entry group");
    }
}

///
unittest
{
    string contents;
    FireOptions options;

    contents = "[Desktop Entry]\nURL=testurl";
    options.flags = FireOptions.FollowLink;
    assertThrown(fireDesktopFile(iniLikeStringReader(contents), null, options));

    contents = "[Group]\nKey=Value";
    options = FireOptions.init;
    assertThrown(fireDesktopFile(iniLikeStringReader(contents), null, options));

    contents = "[Desktop Entry]\nURL=testurl";
    options = FireOptions.init;
    bool wasCalled;
    options.opener = delegate void (string url) {
        assert(url == "testurl");
        wasCalled = true;
    };

    fireDesktopFile(iniLikeStringReader(contents), null, options);
    assert(wasCalled);

    contents = "[Desktop Entry]";
    options = FireOptions.init;
    assertThrown(fireDesktopFile(iniLikeStringReader(contents), null, options));

    contents = "[Desktop Entry]\nURL=testurl";
    options.flags = FireOptions.Exec;
    assertThrown(fireDesktopFile(iniLikeStringReader(contents), null, options));

    contents = "[Desktop Entry]\nExec=whoami";
    options.flags = FireOptions.Link;
    assertThrown(fireDesktopFile(iniLikeStringReader(contents), null, options));

    version(desktopfileFileTest) static if (isFreedesktop) {
        try {
            contents = "[Desktop Entry]\nExec=whoami\nTerminal=true";
            options.flags = FireOptions.Exec;
            wasCalled = false;
            options.terminalDetector = delegate string[] () {wasCalled = true; return null;};
            fireDesktopFile(iniLikeStringReader(contents), null, options);
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
            options.flags = FireOptions.Link | FireOptions.FollowLink;
            options.opener = delegate void (string url) {
                assert(url == "testurl");
                wasCalled = true;
            };

            fireDesktopFile(iniLikeStringReader(contents), null, options);
            assert(wasCalled);
        } catch(Exception e) {

        }
    }
}

/// ditto, but automatically create IniLikeReader from the file.
@trusted void fireDesktopFile(string fileName, FireOptions options = FireOptions.init)
{
    fireDesktopFile(iniLikeFileReader(fileName), fileName, options);
}

/**
 * See $(LINK2 https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s02.html#desktop-file-id, Desktop File ID)
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
                return to!string(fileSplit.join("-"));
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
     * See $(LINK2 https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s02.html#desktop-file-id, Desktop File ID)
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
 * Check if .desktop file is trusted.
 *
 * This is not actually part of Desktop File Specification but many desktop envrionments have this concept.
 * The trusted .desktop file is a file the current user has executable access on or the owner of which is root.
 * This function should be applicable only to desktop files of $(D desktopfile.file.DesktopEntry.Type.Application) type.
 * Note: Always returns true on non-posix systems.
 */
@trusted bool isTrusted(scope string appFileName) nothrow
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
