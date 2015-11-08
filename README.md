# Desktopfile

D library for working with *.desktop* files. Desktop entries in Freedesktop world are akin to shortcuts from Windows world (.lnk files).

[![Build Status](https://travis-ci.org/MyLittleRobo/desktopfile.svg?branch=master)](https://travis-ci.org/MyLittleRobo/desktopfile) [![Coverage Status](https://coveralls.io/repos/MyLittleRobo/desktopfile/badge.svg?branch=master&service=github)](https://coveralls.io/github/MyLittleRobo/desktopfile?branch=master)

The most of desktop environments on Linux and BSD flavors follows [Desktop Entry Specification](http://standards.freedesktop.org/desktop-entry-spec/latest/) today.
The goal of **desktopfile** library is to provide implementation of this specification in D programming language.
Please feel free to propose enchancements or report any related bugs to *Issues* page.

## Platform support

The library is crossplatform for the most part, though there's little sense to use it on systems that don't follow freedesktop specifications.
**desktopfile** is developed and tested on FreeBSD and Debian GNU/Linux.

## Features

### Implemented features

**desktopfile** provides basic features like reading and executing desktop files, and more:

* [Exec](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html) value unquoting and unescaping. Expanding field codes.
* Can rewrite desktop files preserving all comments and the original order of groups.
* Retrieving [Desktop file ID](http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html).
* Support for [Additional application actions](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s10.html).
* Determining default terminal command to run applications with Terminal=true.

### Missing features

Features that currently should be handled by user, but may be implemented in the future versions of library.

* [D-Bus Activation](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s07.html).
* Startup Notification Protocol.
* Copying files to local file system when %f field code is used.
* Starting several instances of application if it supports only %f and not %F.

## Generating documentation

Ddoc:

    dub build --build=docs
    
Ddox:

    dub build --build=ddox

## Running tests

    dub test
    
## Brief

```d
import std.stdio;
import std.array;
import std.process;

import desktopfile;

string filePath = ...;
string[] arguments = ...;

try {
    auto df = new DesktopFile(filePath);
    
    string locale = environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG"))); //Detect current locale.
    
    string name = df.localizedName(locale); //Specific name of the application.
    string genericName = df.localizedGenericName(locale); //Generic name of the application. Show it in menu under the specific name.
    string comment = df.localizedComment(locale); //Show it as tooltip or description.
    
    string iconName = df.iconName(); //Freedesktop icon name.
    
    if (df.hidden()) {
        //User uninstalled desktop file and it should be shown in menus.
    }
    
    string[] onlyShowIn = df.onlyShowIn().array; //If not empty, show this application only in listed desktop environments.
    string[] notShowIn = df.notShowIn().array; //Don't show this application in listed desktop environments.
    
    string[] mimeTypes = df.mimeTypes().array; //MIME types supported by application.
    string[] categories = df.categories().array; //Menu entries where this application should be shown.
    string[] keywords = df.keywords().array; //Keywords can be used to improve searching of the application.
    
    foreach(action; df.byAction()) { //Supported actions.
        string actionName = action.name();
    }
    
    if (df.type() == DesktopFile.Type.Application) {
        //This is application
        string commandLine = df.execString(); //Command line pattern used to start the application.
        try {
            df.startApplication(arguments); //Start application using given arguments. It will be automatically started in terminal emulator if required.
        }
        catch(ProcessException e) { //Failed to start the application.
            stderr.writeln(e.msg); 
        }
        catch(DesktopExecException e) { //Malformed command line pattern.
            stderr.writeln(e.msg); 
        }
    } else if (df.type() == DesktopFile.Type.Link) {
        //This is link to file or web resource.
        string url = df.url(); //URL to open
        
    } else if (df.type() == DesktopFile.Type.Directory) {
        //This is directory or menu section description.
    } else {
        //Type is not defined or unknown, e.g. KDE Service.
        string type = df.value("Type"); //Retrieve value manually as string if you know how to deal with non-standard types.
    }
} 
catch (IniLikeException e) { //Parsing error - file is not desktop file or has errors.
    stderr.writeln(e.msg); 
}

```

## Examples

### Desktop util

Utility that can parse, execute and rewrites .desktop files.

This will start vlc with the first parameter set to $HOME/Music:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/vlc.desktop $HOME/Music
    
This should start command line application in terminal emulator (will be detected automatically):

    dub run desktopfile:desktoputil -- exec /usr/share/applications/python2.7.desktop

Additional application actions are supported too:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/steam.desktop --action=Settings
    
Open link with preferred application:

    dub run desktopfile:desktoputil -- link /usr/share/desktop-base/debian-homepage.desktop

Starts .desktop file defined executable or opens link:

    dub run desktopfile:desktoputil -- start /path/to/file.desktop
    
Parse and write .desktop file to new location (to testing purposes):

    dub run desktopfile:desktoputil -- write /usr/share/applications/vlc.desktop $HOME/Desktop/vlc.desktop

Read basic information about desktop file:

    dub run desktopfile:desktoputil -- read /usr/share/applications/kde4/kate.desktop
 
### Desktop test

Parses all .desktop files in system's applications paths (usually /usr/local/share/applicatons and /usr/share/applications) and on the user's Desktop.
Writes errors (if any) to stderr.
Use this example to check if the desktopfile library can parse all .desktop files on your system.

    dub run desktopfile:desktoptest

To print all directories examined by desktoptest to stdout, add --verbose flag:

    dub run desktopfile:desktoptest -- --verbose

Start desktoptest on specified directories:

    dub run desktopfile:desktoptest -- /path/to/applications /anotherpath/to/applications
    
Example using cmd on Windows (KDE installed):

    set KDE_SHARE="%SYSTEMDRIVE%\ProgramData\KDE\share"
    dub run desktopfile:desktoptest -- %KDE_SHARE%\applications %KDE_SHARE%\templates %KDE_SHARE%\desktop-directories %KDE_SHARE%\autostart
    
    