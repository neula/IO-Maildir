NAME
====

`IO::Maildir` provides functions for safely dealing with maildir directories.

SYNOPSIS
========

    use IO::Maildir;
    my $inbox = maildir "~/mail/INBOX";
    $inbox.create;
    my $msg = $inbox.receive($somemail);

DESCRIPTION
===========

`IO::Maildir` tries to implement the [maildir](https://cr.yp.to/proto/maildir.html) spec. It can serve as a basis for mail delivery agents or mail user agents (or a mixture of both). The named `agent` parameter can be used to set the behaviour for some methods. Default behaviour can be changed by setting `$maildir-agent`.

### sub maildir

    sub maildir($path --> IO::Maildir)

Returns a maildir object from `$path`. `$path` will be coerced to IO.

### maildir-agent

    our Agent $maildir-agent = IO::Maildir::DELIVERY

Set this to either `IO::Maildir::DELIVERY` or `IO::Maildir::USER`. Affects behaviour of following methods:

  * `IO::Maildir::File`: `flag`, `move`

  * `IO::Maildir`: `walk`

class IO::Maildir
-----------------

Class for maildir directories.

    my $maildir = IO::Maildir.new "~/Mail/INBOX";
    my $maildir = maildir "~/Mail/INBOX" # Same

### method create

    method create( --> IO::Maildir) { ... }

Creates a new maildir directory including its cur, new and tmp subdirectories.

### method receive

    multi method receive(IO $mail --> IO::Maildir::File) { ... }
    multi method receive(Str $mail --> IO::Maildir::File) { ... }

Adds a new file to the maildir. `receive` will always deliver to new and write the file to tmp first if neccessary. Note that receiving an IO object will delete the original file.

### method walk

    method walk(:$all, :$agent = $maildir-agent --> Seq) { ... }

Returns the new mails in the maildir (or all if you set it). Newest mails will be returned first.

If called with `$agent = IO::Maildir::USER` it will also do the following actions:

1. Look inside tmp and delete files older than 36 hours. 2. Move files from new to cur **after** the returned Seq is consumed.

class IO::Maildir::Files
------------------------

Handle for files inside a maildir.

    #Create from IO::Path
    my $file = IO::Maildir::File.new( path => "~/Mail/INBOX/cur/uniquefilename:2,".IO );
    #Create from maildir
    my $file = IO::Maildir::File.new( dir => $maildir, name => "uniquefilename:2," );

Usually you don't need to do anything of the above, since you will receive your `IO::Maildir::File` objects from `IO::Maildir`s methods.

### attribute dir

    has IO::Maildir $.dir

Points to the maildir containing this file.

### attribute name

    has $.name

Complete file name including flags and stuff.

### method IO

    method IO( --> IO ) { ... }

Returns the `IO::Path` object pointing to the file.

### method flags

    method flags( --> Set ) { ... }

Returns the `Set` of flags set for this file.

### method flag

    multi method flag(:$agent = $maildir-agent, *%flags)
    multi method flag(
	    %flags where *.keys.Set ⊆ <P R S T D>.Set,
	    :$agent = $maildir-agent)

Use this to set flags. Fails if `$agent` is set to `IO::Maildir::DELIVERY`. This will also move the file to cur, because it has been seen by the MUA.

### method move

    multi method move(IO::Maildir $maildir, Agent :$agent = $maildir-agent --> IO::Maildir::File) { ... }
    multi method move (IO $iodir, Agent :$agent = $maildir-agent --> IO::Maildir::File) { ... }

Moves the file to a different maildir and returns the updated file-handle. If called in `IO::Maildir::DELIVERY` mode, the file will be moved to new and old flags will be removed. If called in `IO::Maildir::USER` mode, it will be moved to cur and flags will be preserved.

AUTHOR
======

neula <thomas@famsim.de>

Source can be located at: [https://github.com/neula/IO-Maildir](https://github.com/neula/IO-Maildir) . Comments and Pull Requests are welcome.

LICENSE
=======

This library is free software; you may redistribute or modify it under the Artistic License 2.0.

