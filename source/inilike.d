module inilike;

private {
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
}

private alias LocaleTuple = Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier");
private alias KeyValueTuple = Tuple!(string, "key", string, "value");

/** Retrieves current locale probing environment variables LC_TYPE, LC_ALL and LANG (in this order)
 * Returns: locale in posix form or empty string if could not determine locale
 */
string currentLocale() @safe nothrow
{
    static string cache;
    if (cache is null) {
        try {
            cache = environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG")));
        }
        catch(Exception e) {
            
        }
        if (cache is null) {
            cache = "";
        }
    }
    return cache;
}

/**
 * Makes locale name based on language, country, encoding and modifier.
 * Returns: locale name in form lang_COUNTRY.ENCODING@MODIFIER
 */
string makeLocaleName(string lang, string country = null, string encoding = null, string modifier = null) pure nothrow @safe
{
    return lang ~ (country.length ? "_"~country : "") ~ (encoding.length ? "."~encoding : "") ~ (modifier.length ? "@"~modifier : "");
}

/**
 * Parses locale name into the tuple of 4 values corresponding to language, country, encoding and modifier
 * Returns: Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier")
 */
auto parseLocaleName(string locale) pure nothrow @nogc @trusted
{
    auto modifiderSplit = findSplit(locale, "@");
    auto modifier = modifiderSplit[2];
    
    auto encodongSplit = findSplit(modifiderSplit[0], ".");
    auto encoding = encodongSplit[2];
    
    auto countrySplit = findSplit(encodongSplit[0], "_");
    auto country = countrySplit[2];
    
    auto lang = countrySplit[0];
    
    return LocaleTuple(lang, country, encoding, modifier);
}

/**
 * Constructs localized key name from key and locale.
 * Returns: localized key in form key[locale]. Automatically omits locale encoding if present.
 */
string localizedKey(string key, string locale) pure nothrow @safe
{
    auto t = parseLocaleName(locale);
    if (!t.encoding.empty) {
        locale = makeLocaleName(t.lang, t.country, null, t.modifier);
    }
    return key ~ "[" ~ locale ~ "]";
}

/**
 * Ditto, but constructs locale name from arguments.
 */
string localizedKey(string key, string lang, string country, string modifier = null) pure nothrow @safe
{
    return key ~ "[" ~ makeLocaleName(lang, country, null, modifier) ~ "]";
}

/** 
 * Separates key name into non-localized key and locale name.
 * If key is not localized returns original key and empty string.
 * Returns: tuple of key and locale name;
 */
Tuple!(string, string) separateFromLocale(string key) nothrow @nogc @trusted {
    if (key.endsWith("]")) {
        auto t = key.findSplit("[");
        if (t[1].length) {
            return tuple(t[0], t[2][0..$-1]);
        }
    }
    return tuple(key, string.init);
}

/**
 * Tells whether the character is valid for desktop entry key.
 * Note: This does not include characters presented in locale names.
 */
bool isValidKeyChar(char c) pure nothrow @nogc @safe
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
}


/**
 * Tells whethe the string is valid dekstop entry key.
 * Note: This does not include characters presented in locale names. Use $(B separateFromLocale) to get non-localized key to pass it to this function
 */
bool isValidKey(string key) pure nothrow @nogc @safe
{
    if (key.empty) {
        return false;
    }
    for (size_t i = 0; i<key.length; ++i) {
        if (!key[i].isValidKeyChar()) {
            return false;
        }
    }
    return true;
}

/**
 * Tells whether the dekstop entry value presents true
 */
bool isTrue(string value) pure nothrow @nogc @safe {
    return (value == "true" || value == "1");
}

/**
 * Tells whether the desktop entry value presents false
 */
bool isFalse(string value) pure nothrow @nogc @safe {
    return (value == "false" || value == "0");
}

/**
 * Check if the desktop entry value can be interpreted as boolean value.
 */
bool isBoolean(string value) pure nothrow @nogc @safe {
    return isTrue(value) || isFalse(value);
}
/**
 * Escapes string by replacing special symbols with escaped sequences. 
 * These symbols are: '\\' (backslash), '\n' (newline), '\r' (carriage return) and '\t' (tab).
 * Note: 
 *  Currently the library stores values as they were loaded from file, i.e. escaped. 
 *  To keep things consistent you should take care about escaping the value before inserting. The library will not do it for you.
 * Returns: Escaped string.
 * Example:
----
assert("\\next\nline".escapeValue() == `\\next\nline`); // notice how the string on the right is raw.
----
 */
string escapeValue(string value) @trusted nothrow pure {
    return value.replace("\\", `\\`).replace("\n", `\n`).replace("\r", `\r`).replace("\t", `\t`);
}

string doUnescape(string value, in Tuple!(char, char)[] pairs) @trusted nothrow pure {
    auto toReturn = appender!string();
    
    for (size_t i = 0; i < value.length; i++) {
        if (value[i] == '\\') {
            if (i < value.length - 1) {
                char c = value[i+1];
                auto t = pairs.find!"a[0] == b[0]"(tuple(c,c));
                if (!t.empty) {
                    toReturn.put(t.front[1]);
                    i++;
                    continue;
                }
            }
        }
        toReturn.put(value[i]);
    }
    return toReturn.data;
}


/**
 * Unescapes string. You should unescape values returned by library before displaying until you want keep them as is (e.g., to allow user to edit values in escaped form).
 * Returns: Unescaped string.
 * Example:
-----
assert(`\\next\nline`.unescapeValue() == "\\next\nline"); // notice how the string on the left is raw.
----
 */
string unescapeValue(string value) @trusted nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('s', ' '),
       tuple('n', '\n'),
       tuple('r', '\r'),
       tuple('t', '\t'),
       tuple('\\', '\\')
    ];
    return doUnescape(value, pairs);
}

string unescapeExec(string str) @trusted nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
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
    ];
    return doUnescape(str, pairs);
}

struct IniLikeLine
{
    enum Type
    {
        None = 0,
        Comment = 1,
        KeyValue = 2,
        GroupStart = 4
    }
    
    static IniLikeLine fromComment(string comment) @safe {
        return IniLikeLine(comment, null, Type.Comment);
    }
    
    static IniLikeLine fromGroupName(string groupName) @safe {
        return IniLikeLine(groupName, null, Type.GroupStart);
    }
    
    static IniLikeLine fromKeyValue(string key, string value) @safe {
        return IniLikeLine(key, value, Type.KeyValue);
    }
    
    string comment() const @safe @nogc nothrow {
        return _type == Type.Comment ? _first : null;
    }
    
    string key() const @safe @nogc nothrow {
        return _type == Type.KeyValue ? _first : null;
    }
    
    string value() const @safe @nogc nothrow {
        return _type == Type.KeyValue ? _second : null;
    }
    
    string groupName() const @safe @nogc nothrow {
        return _type == Type.GroupStart ? _first : null;
    }
    
    Type type() const @safe @nogc nothrow {
        return _type;
    }
    
    void makeNone() @safe @nogc nothrow {
        _type = Type.None;
    }
    
private:
    string _first;
    string _second;
    Type _type = Type.None;
}

final class IniLikeGroup
{
private:
    this(string name) @safe @nogc nothrow {
        _name = name;
    }
    
public:
    
    /**
     * Returns: the value associated with the key
     * Note: it's an error to access nonexistent value
     */
    string opIndex(string key) const @safe @nogc nothrow {
        auto i = key in _indices;
        assert(_values[*i].type == IniLikeLine.Type.KeyValue);
        assert(_values[*i].key == key);
        return _values[*i].value;
    }
    
    /**
     * Inserts new value or replaces the old one if value associated with key already exists.
     * Returns: inserted/updated value
     * Throws: $(B Exception) if key is not valid
     * See_Also: isValidKey
     */
    string opIndexAssign(string value, string key) @safe {
        enforce(separateFromLocale(key)[0].isValidKey(), "key is invalid");
        auto pick = key in _indices;
        if (pick) {
            return (_values[*pick] = IniLikeLine.fromKeyValue(key, value)).value;
        } else {
            _indices[key] = _values.length;
            _values ~= IniLikeLine.fromKeyValue(key, value);
            return value;
        }
    }
    /**
     * Ditto, but also allows to specify the locale.
     * See_Also: setLocalizedValue, localizedValue
     */
    string opIndexAssign(string value, string key, string locale) @safe {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    /**
     * Tells if group contains value associated with the key.
     */
    bool contains(string key) const @safe @nogc nothrow {
        return value(key) !is null;
    }
    
    /**
     * Returns: the value associated with the key, or defaultValue if group does not contain item with this key.
     */
    string value(string key, string defaultValue = null) const @safe @nogc nothrow {
        auto pick = key in _indices;
        if (pick) {
            if(_values[*pick].type == IniLikeLine.Type.KeyValue) {
                assert(_values[*pick].key == key);
                return _values[*pick].value;
            }
        }
        return defaultValue;
    }
    
    /**
     * Performs locale matching lookup as described in $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html, Localized values for keys).
     * If locale is null it calls currentLocale to get the locale.
     * Returns: the localized value associated with key and locale, or defaultValue if group does not contain item with this key.
     */
    string localizedValue(string key, string locale = null, string defaultValue = null) const @safe nothrow {
        if (locale is null) {
            locale = currentLocale();
        }
        
        //Any ideas how to get rid of this boilerplate and make less allocations?
        auto t = parseLocaleName(locale);
        auto lang = t.lang;
        auto country = t.country;
        auto modifier = t.modifier;
        
        if (lang.length) {
            string pick;
            
            if (country.length && modifier.length) {
                pick = value(localizedKey(key, locale));
                if (pick !is null) {
                    return pick;
                }
            }
            
            if (country.length) {
                pick = value(localizedKey(key, lang, country));
                if (pick !is null) {
                    return pick;
                }
            }
            
            if (modifier.length) {
                pick = value(localizedKey(key, lang, null, modifier));
                if (pick !is null) {
                    return pick;
                }
            }
            
            pick = value(localizedKey(key, lang, null));
            if (pick !is null) {
                return pick;
            }
        }
        
        return value(key, defaultValue);
    }
    
    /**
     * Same as localized version of opIndexAssign, but uses function syntax.
     */
    void setLocalizedValue(string key, string locale, string value) @safe {
        this[key, locale] = value;
    }
    
    /**
     * Removes entry by key. To remove localized values use localizedKey.
     */
    void removeEntry(string key) @safe nothrow {
        auto pick = key in _indices;
        if (pick) {
            _values[*pick].makeNone();
        }
    }
    
    /**
     * Returns: range of Tuple!(string, "key", string, "value")
     */
    auto byKeyValue() const @safe @nogc nothrow {
        return _values.filter!(v => v.type == IniLikeLine.Type.KeyValue).map!(v => KeyValueTuple(v.key, v.value));
    }
    
    /**
     * Returns: the name of group
     */
    string name() const @safe @nogc nothrow {
        return _name;
    }
    
    auto byLine() const {
        return _values;
    }
    
    void addComment(string comment) {
        _values ~= IniLikeLine.fromComment(comment);
    }
    
private:
    size_t[string] _indices;
    IniLikeLine[] _values;
    string _name;
}

/**
 * Exception thrown on the file read error.
 */
class IniLikeException : Exception
{
    this(string msg, size_t lineNumber, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _lineNumber = lineNumber;
    }
    
    ///Number of line in desktop file where the exception occured, starting from 1. Don't be confused with $(B line) property of $(B Throwable).
    size_t lineNumber() const nothrow @safe @nogc {
        return _lineNumber;
    }
    
private:
    size_t _lineNumber;
}

auto iniLikeFileReader(string fileName)
{
    return iniLikeRangeReader(File(fileName, "r").byLine().map!(s => s.idup));
}

auto iniLikeStringReader(string contents)
{
    return iniLikeRangeReader(contents.splitLines());
}

auto iniLikeRangeReader(Range)(Range byLine)
{
    return byLine.map!(function(string line) {
        line = strip(line);
        if (line.empty || line.startsWith("#")) {
            return IniLikeLine.fromComment(line);
        } else if (line.startsWith("[") && line.endsWith("]")) {
            return IniLikeLine.fromGroupName(line[1..$-1]);
        } else {
            auto t = line.findSplit("=");
            auto key = t[0].stripRight();
            auto value = t[2].stripLeft();
            
            if (t[1].length) {
                return IniLikeLine.fromKeyValue(key, value);
            } else {
                return IniLikeLine();
            }         
        }
    });
}

class IniLikeFile
{
public:
    ///Flags to manage .ini like file reading
    enum ReadOptions
    {
        noOptions = 0, /// Read all groups and skip comments and empty lines.
        firstGroupOnly = 1, /// Ignore other groups than the first one.
        preserveComments = 2 /// Preserve comments and empty lines. Use this when you want to preserve them across writing.
    }
    
    /**
     * Reads desktop file from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeException) if error occured while reading the file.
     */
    static IniLikeFile loadFromFile(string fileName, ReadOptions options = ReadOptions.noOptions) @trusted {
        return new IniLikeFile(iniLikeFileReader(fileName), options, fileName);
    }
    
    /**
     * Reads desktop file from string.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing the contents.
     */
    static IniLikeFile loadFromString(string contents, ReadOptions options = ReadOptions.noOptions, string fileName = null) @trusted {
        return new IniLikeFile(iniLikeStringReader(contents), options, fileName);
    }
    
    this() {
        
    }
    
    this(Range)(Range byLine, ReadOptions options = ReadOptions.noOptions, string fileName = null) @trusted
    {
        size_t lineNumber = 0;
        IniLikeGroup currentGroup;
        
        try {
            foreach(line; byLine)
            {
                lineNumber++;
                final switch(line.type)
                {
                    case IniLikeLine.Type.Comment:
                    {
                        if (options & ReadOptions.preserveComments) {
                            if (currentGroup is null) {
                                addFirstComment(line.comment);
                            } else {
                                currentGroup.addComment(line.comment);
                            }
                        }
                    }
                    break;
                    case IniLikeLine.Type.GroupStart:
                    {
                        enforce(line.groupName.length, "empty group name");
                        enforce(group(line.groupName) is null, "group is defined more than once");
                        
                        currentGroup = addGroup(line.groupName);
                        
                        if (options & ReadOptions.firstGroupOnly) {
                            break;
                        }
                    }
                    break;
                    case IniLikeLine.Type.KeyValue:
                    {
                        enforce(currentGroup, "met key-value pair before any group");
                        currentGroup[line.key] = line.value;
                    }
                    break;
                    case IniLikeLine.Type.None:
                    {
                        throw new Exception("not key-value pair, nor group start nor comment");
                    }
                }
            }
            
            _fileName = fileName;
        }
        catch (Exception e) {
            throw new IniLikeException(e.msg, lineNumber, e.file, e.line, e.next);
        }
    }
    
    /**
     * Returns: IniLikeGroup instance associated with groupName or $(B null) if not found.
     */
    inout(IniLikeGroup) group(string groupName) @safe @nogc nothrow inout {
        auto pick = groupName in _groupIndices;
        if (pick) {
            return _groups[*pick];
        }
        return null;
    }
    
    /**
     * Creates new group usin groupName.
     * Returns: newly created instance of IniLikeGroup.
     * Throws: Exception if group with such name already exists or groupName is empty.
     */
    IniLikeGroup addGroup(string groupName) @safe {
        enforce(groupName.length, "group name is empty");
        
        auto iniLikeGroup = new IniLikeGroup(groupName);
        enforce(group(groupName) is null, "group already exists");
        _groupIndices[groupName] = _groups.length;
        _groups ~= iniLikeGroup;
        
        return iniLikeGroup;
    }
    
    /**
     * Removes group by name.
     */
    void removeGroup(string groupName) @safe nothrow {
        auto pick = groupName in _groupIndices;
        if (pick) {
            _groups[*pick] = null;
        }
    }
    
    /**
     * Range of groups in order how they were defined in file.
     */
    auto byGroup() inout {
        return _groups[];
    }
    
    /**
     * Saves object to file using .ini like format.
     * Throws: ErrnoException if the file could not be opened or an error writing to the file occured.
     */
    void saveToFile(string fileName) const {
        auto f = File(fileName, "w");
        void dg(string line) {
            f.writeln(line);
        }
        save(&dg);
    }
    
    /**
     * Saves object to string using .ini like format.
     */
    string saveToString() const {
        auto a = appender!(string[])();
        void dg(string line) {
            a.put(line);
        }
        save(&dg);
        return a.data.join("\n");
    }
    
    private alias SaveDelegate = void delegate(string);
    
    private void save(SaveDelegate sink) const {
        foreach(line; firstComments()) {
            sink(line);
        }
        
        foreach(group; byGroup()) {
            sink("[" ~ group.name ~ "]");
            foreach(line; group._values) {
                if (line.type == IniLikeLine.Type.Comment) {
                    sink(line.comment);
                } else if (line.type == IniLikeLine.Type.KeyValue) {
                    sink(line.key ~ "=" ~ line.value);
                }
            }
        }
    }
    
    /**
     * Returns: file name as was specified on the object creation.
     */
    string fileName() @safe @nogc nothrow const {
        return  _fileName;
    }
    
protected:
    auto firstComments() const nothrow @safe @nogc {
        return _firstComments;
    }
    
    void addFirstComment(string line) nothrow @safe {
        _firstComments ~= line;
    }
    
private:
    string _fileName;
    size_t[string] _groupIndices;
    IniLikeGroup[] _groups;
    string[] _firstComments;
}

unittest
{
    //Test locale-related functions
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", null, null, "mod") == "ru@mod");
    
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    assert(parseLocaleName("ru_RU") == tuple("ru", "RU", string.init, string.init));
    
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru_RU.UTF-8") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
    
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    //Test locale matching lookup
    auto group = new IniLikeGroup("Entry");
    assert(group.name == "Entry"); 
    group["Name"] = "Programmer";
    group["Name[ru_RU]"] = "Разработчик";
    group["Name[ru@jargon]"] = "Кодер";
    group["Name[ru]"] = "Программист";
    group["GenericName"] = "Program";
    group["GenericName[ru]"] = "Программа";
    assert(group["Name"] == "Programmer");
    assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
    assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
    assert(group.localizedValue("Name", "ru") == "Программист");
    assert(group.localizedValue("Name", "nonexistent locale") == "Programmer");
    assert(group.localizedValue("GenericName", "ru_RU") == "Программа");
    
    //Test escaping and unescaping
    assert("\\next\nline".escapeValue() == `\\next\nline`);
    assert(`\\next\nline`.unescapeValue() == "\\next\nline");
}
