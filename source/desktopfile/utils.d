/**
 * Utility functions for reading and executing desktop files.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
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

private @safe bool needQuoting(string arg) nothrow pure
{
    import std.uni : isWhite;
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
 * Apply unquoting to Exec value making it into an array of escaped arguments. It automatically performs quote-related unescaping. Returned values are still escaped as by general rule. Read more: [specification](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html).
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
 *  Parsed arguments still may contain field codes and double percent symbols that should be appropriately expanded before passing to spawnProcess.
 * Throws:
 *  DesktopExecException if string can't be unquoted.
 * See_Also:
 *  unquoteExecString, expandExecArgs
 */
@trusted string[] parseExecString(string execString) pure
{
    return execString.unquoteExecString().map!(s => unescapeValue(s)).array;
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
 *  displayName = name of application used that inserted in the place of %c field code.
 *  fileName = name of desktop file that inserted in the place of %k field code.
 * Throws:
 *  DesktopExecException if command line contains unknown field code.
 * See_Also:
 *  parseExecString
 */
@trusted string[] expandExecArgs(in string[] execArgs, in string[] urls = null, string iconName = null, string displayName = null, string fileName = null) pure
{
    string[] toReturn;
    foreach(token; execArgs) {
        if (token == "%F") {
            toReturn ~= urls;
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
                                expand(token, expanded, restPos, i, urls.front);
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
    assert(expandExecArgs(["program path", "%f%%%f"], ["file"]) == ["program path", "file%file"]);
    assert(expandExecArgs(["program path"], ["one", "two"]) == ["program path"]);
    assert(expandExecArgs(["program path", "%f"], ["one", "two"]) == ["program path", "one"]);
    assert(expandExecArgs(["program path", "%F"], ["one", "two"]) == ["program path", "one", "two"]);
    
    assert(expandExecArgs(["program path", "--location=%k", "--myname=%c"]) == ["program path", "--location=", "--myname="]);
    assert(expandExecArgs(["program path", "%k", "%c"]) == ["program path", "", ""]);
    assertThrown!DesktopExecException(expandExecArgs(["program name", "%y"]));
    assertThrown!DesktopExecException(expandExecArgs(["program name", "--file=%x"]));
    assertThrown!DesktopExecException(expandExecArgs(["program name", "--files=%F"]));
}

/**
 * Unquote, unescape Exec string and expand field codes substituting them with appropriate values.
 * Throws:
 *  DesktopExecException if string can't be unquoted, unquoted command line is empty or it has unknown field code.
 * See_Also:
 *  expandExecArgs, parseExecString
 */
@trusted string[] expandExecString(string execString, in string[] urls = null, string iconName = null, string displayName = null, string fileName = null) pure
{
    auto execArgs = parseExecString(execString);
    if (execArgs.empty) {
        throw new DesktopExecException("No arguments. Missing or empty Exec value");
    }
    return expandExecArgs(execArgs, urls, iconName, displayName, fileName);
}

///
unittest
{
    assert(expandExecString(`"quoted program" %i -w %c --file=%k %U %D %u %f %F`, ["one", "two"], "folder", "Программа", "/example.desktop") == ["quoted program", "--icon", "folder", "-w", "Программа", "--file=/example.desktop", "one", "two", "one", "one", "one", "two"]);
    
    assertThrown!DesktopExecException(expandExecString(`program %f %y`)); //%y is unknown field code.
    assertThrown!DesktopExecException(expandExecString(``));
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
        
        static string findExecutable(string fileName) nothrow {
            try {
                foreach(string path; std.algorithm.splitter(environment.get("PATH"), ':')) {
                    if (path.empty) {
                        continue;
                    }
                    
                    string candidate = checkExecutable(buildPath(absolutePath(path), fileName));
                    if (candidate.length) {
                        return candidate;
                    }
                }
            } catch (Exception e) {
                
            }
            return null;
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

unittest
{
    import isfreedesktop;
    static if (isFreedesktop) {
        import xdgpaths;
        
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

package void readNeededKeys(Group)(Group g, string locale, 
                            out string iconName, out string name, 
                            out string execString, out string url, 
                            out string workingDirectory, out bool terminal)
{
    string bestLocale;
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
                        auto lv = chooseLocalizedValue(locale, kl[1], value, bestLocale, name);
                        bestLocale = lv[0];
                        name = lv[1];
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
    
    string iconName, name, execString, url, workingDirectory;
    bool terminal;
    readNeededKeys(reader.byGroup().front, "ru_RU", iconName, name , execString, url, workingDirectory, terminal);
    assert(iconName == "folder");
    assert(execString == "whoami");
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
 *  DesktopExecException if exec string is invalid.
 *  Exception on other errors.
 * See_Also: ShootOptions
 */
@trusted void shootDesktopFile(IniLikeReader)(IniLikeReader reader, string fileName = null, ShootOptions options = ShootOptions.init)
{
    enforce(options.flags & (ShootOptions.Exec|ShootOptions.Link), "At least one of the options Exec or Link must be provided");
    
    string iconName, name, execString, url, workingDirectory;
    bool terminal;
    
    foreach(g; reader.byGroup) {
        if (g.name == "Desktop Entry") {
            readNeededKeys(g, options.locale, iconName, name , execString, url, workingDirectory, terminal);
            
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
 *  fileName = path of desktop file.
 *  appPaths = range of base application paths to check if this file belongs to one of them.
 * Returns: Desktop file ID or empty string if file does not have an ID.
 * See_Also: desktopfile.paths.applicationsPaths
 */
@trusted string desktopId(Range)(string fileName, Range appPaths) nothrow if (isInputRange!Range && is(ElementType!Range : string))
{
    try {
        string absolute = fileName.absolutePath;
        foreach (path; appPaths) {
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
     *  fileName = path of desktop file.
     * Note: This function retrieves applications paths each time it's called and therefore can impact performance. To avoid this issue use overload with argument.
     * See_Also: desktopfile.paths.applicationsPaths
     */
    @trusted string desktopId(string fileName) nothrow
    {
        import desktopfile.paths;
        return desktopId(fileName, applicationsPaths());
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
