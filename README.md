About
=====

**IO::Maildir** provides functions for safely dealing with maildir directories.
It can be configured to act like a mail user agent or a mail delivery agent.

Synopsis
========
	use IO::Maildir;
	my $inbox = maildir "~/mail/INBOX";
	$inbox.create;
	my $msg = $inbox.receive($somemail);

License
=======

This library is free software; you may redistribute or modify it under the Artistic License 2.0.
