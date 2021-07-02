unit class IO::Maildir;

enum Agent ( DELIVERY => 'new', USER => 'cur' );

#weird stuff some MDAs set for example S=<filesize>
my regex baseflags { [\,<:Lu>\=\d+]* }
my regex mailflags { \:2 [\,|(P|R|S|T|D|F)|(<:Ll>)]* $ }


my $deliveries = 0;
my $msgdirs = <cur new tmp>;

our $maildir-agent is export = DELIVERY;

sub is-maildir(IO $path --> Bool ) is export {
    ?($path ~~ :d && $path.dir.grep( *.basename ∈ $msgdirs) == $msgdirs);
}

sub is-mail($file) { $file ~~ ! / ^^\. / }

sub uniq(--> Str ) {
    my ($sec, $usec) = ( .truncate, $_ - .truncate) given now.Num;
    my ($init, $init-usec) = ( .truncate, $_ - .truncate) given $*INIT-INSTANT;
    #This tries to mimic maildrops naming scheme (courier-mta.org/maildir.html).
    #$*INIT-INSTANT (with 'S' for 'startup') is used instead of the
    #message-files device number, which can't be obtained using IO::PATH.
    ( ~$sec ~ '.M' ~ $usec.substr(2) ~ 'P' ~ ~$*PID ~ 'S' ~ ~$init
      ~ 'U' ~ $init-usec.base(16).substr(2)
      ~ '_' ~ ~$deliveries++ ~ '.' ~ $*KERNEL.hostname )
}

class File { ... }
trusts File;

class File does IO {
    has IO::Maildir $.dir;
    has $.name;

    method IO( --> IO ) {
	for <new cur>.map: { $!dir.IO.add($_) } {
	    ($_ ~~ :f ?? return $_ !! Nil) given .add($!name);
	}
    }
    method delivered( --> Instant ) { $.IO.modified }
    method flags( --> Set ) { set $/[*;*]».Str if ~$!name ~~ &mailflags }
    multi method flag(
	%flags where *.keys.Set ⊆ <P R S T D>.Set,
	:$agent = $maildir-agent)
    {
	fail "Setting flags is reserved for USER agents." if $agent ~~ DELIVERY;
	my $uniq = $!name;
	my %new;
	if ($uniq ~~ &mailflags) {
	    %new.append( $/.map: ~* => True );
	    $uniq = $uniq.chop($/.Str.chars);
	}
	for %flags {
	    if .value {
		%new{.key} = True;
	    } else {
		%new{.key} = False;
	    }
	}
	$uniq ~= ":2," ~ ( join('')
			   <== sort()
			   <== map( *.key )
			   <== grep( *.value )
			   <== %new);
	.rename(.dirname.IO.add: "../cur/" ~ $uniq) given $.IO;
	$!name = $uniq;
    }
    multi method flag(:$agent = $maildir-agent, *%flags) {
	self.flag(%flags, agent => $agent);
    }
    multi method move(IO::Maildir $maildir, Agent :$agent = $maildir-agent --> File) {
	fail Nil unless $maildir ~~ :is-maildir;
	given $maildir!IO::Maildir::rename-or-mv( $.IO, agent => $agent ) {
	    .flag(%.flags, agent => USER) if $agent ~~ USER;
	    $_;
	}
    }
    multi method move (IO $iodir, Agent :$agent = $maildir-agent --> File) {
	nextwith maildir($iodir), agent => $agent;
    }
    submethod TWEAK(IO :$path) {
	return without $path;
	given maildir $path.dirname.IO.dirname {
	    ($!dir, $!name) = ($_, $path.basename) if :is-maildir;
	}
    }
}

has $.path handles <IO d e f l r rw rwx s w x z>;

method new(|c) { self.bless( path => IO::Path.new(|c)) }
method is-maildir( --> Bool ) { is-maildir($.path) }
method create( --> IO::Maildir) {
    $msgdirs.map( { mkdir( $!path.add: $_ ) } );
    self
}
multi method receive(IO $mail --> IO::Maildir::File) {
    fail Nil unless self ~~ :is-maildir;
    self!rename-or-mv($mail, agent => DELIVERY);
}
multi method receive(Str $mail --> IO::Maildir::File) {
    fail Nil unless self ~~ :is-maildir;
    my $mail-path = $!path.add("tmp/" ~ uniq());
    $mail-path.spurt($mail, :createonly);
    self!rename-or-mv($mail-path,
		      uniq => $mail-path.basename,
		      agent => DELIVERY);
}
method !rename-or-mv(IO $path,
		     Str :$uniq is copy = uniq(),
		     :$agent = $maildir-agent --> IO::Maildir::File)
{
    my &padd-uniq = { $!path.add: ~($_ // $agent.value) ~ "/" ~ $uniq };

    #Can tmp be skipped?
    $path.rename( &padd-uniq.(), :createonly );
    CATCH {
	#Nope
	when X::IO::Rename {
	    #If this fails again it is most likely a bug with the uniqueness
	    #of the generated filenames.
	    $path.move(&padd-uniq.("tmp"), :createonly);
	    $path.rename(&padd-uniq.(), :createonly );
	    .resume
	}
    }
    #TODO: find out if there are other useful base-flags.
    #maildrop and others use ',S' for quotas so lets add this.
    unless $uniq ~~ &mailflags {
	given &padd-uniq.() {
	    $uniq = $uniq ~ ',S=' ~$_.s;
	    $_.rename( .dirname.IO.add($uniq), :createonly);
	}
    }
    IO::Maildir::File.new( dir => self, name => $uniq )
}
method !mails-from-dir(IO $dir) {
    sort( *.delivered.Num*(-1) )
    <== map({ IO::Maildir::File.new: dir => self, name => .basename })
    <== $dir.dir: test => &is-mail;
}
method walk(:$all, :$agent = $maildir-agent --> Seq) {
    if $agent ~~ USER {
	for dir( $!path.add("tmp"), test => &is-mail ) {
	    # Maildir spec expects us to clean up files in tmp,
	    # which haven't been touched for 36 hours.
	    .unlink if .accessed - now > 129600;
	}
    }
    my @new-mails = self!mails-from-dir($!path.add: "new").cache;
    gather {
	take $_ for @new-mails;
	if ?$all {
	    take $_ for self!mails-from-dir($!path.add: "cur");
	}
	#Seen mails should be moved to cur (if it hasn't happened before).
	if $agent ~~ USER {
	    for @new-mails {
		.flag( agent => USER ) if .IO.dirname.IO.basename ~~ "new";
	    }
	}
    }
}

sub maildir($path --> IO::Maildir) is export { IO::Maildir.new( $path.IO ) }

=begin pod

=head1 NAME

C<IO::Maildir> provides functions for safely dealing with maildir directories.

=head1 SYNOPSIS

=begin code
use IO::Maildir;
my $inbox = maildir "~/mail/INBOX";
$inbox.create;
my $msg = $inbox.receive($somemail);
=end code

=head1 DESCRIPTION

C<IO::Maildir> tries to implement the L<maildir|https://cr.yp.to/proto/maildir.html> spec.
It can serve as a basis for mail delivery agents or mail user agents (or a mixture of both).
The named C<agent> parameter can be used to set the behaviour for some methods.
Default behaviour can be changed by setting C<$maildir-agent>.

=head3 sub maildir

=begin code
sub maildir($path --> IO::Maildir)
=end code

Returns a maildir object from C<$path>.
C<$path> will be coerced to IO.

=head3 maildir-agent

=begin code
our Agent $maildir-agent = IO::Maildir::DELIVERY
=end code

Set this to either C<IO::Maildir::DELIVERY> or C<IO::Maildir::USER>. Affects behaviour of following methods:
=item C<IO::Maildir::File>: C<flag>, C<move>
=item C<IO::Maildir>: C<walk>

=head2 class IO::Maildir

Class for maildir directories.

=begin code
my $maildir = IO::Maildir.new "~/Mail/INBOX";
my $maildir = maildir "~/Mail/INBOX" # Same
=end code

=head3 method create

=begin code
method create( --> IO::Maildir) { ... }
=end code

Creates a new maildir directory including its cur, new and tmp subdirectories.

=head3 method receive

=begin code
multi method receive(IO $mail --> IO::Maildir::File) { ... }
multi method receive(Str $mail --> IO::Maildir::File) { ... }
=end code

Adds a new file to the maildir. C<receive> will always deliver to new and write the
file to tmp first if neccessary.
Note that receiving an IO object will delete the original file.

=head3 method walk

=begin code
method walk(:$all, :$agent = $maildir-agent --> Seq) { ... }
=end code

Returns the new mails in the maildir (or all if you set it).
Newest mails will be returned first.

If called with C<$agent = IO::Maildir::USER> it will also do the following actions:

=item 1. Look inside tmp and delete files older than 36 hours.
=item 2. Move files from new to cur B<after> the returned Seq is consumed.

=head2 class IO::Maildir::Files

Handle for files inside a maildir.

=begin code
#Create from IO::Path
my $file = IO::Maildir::File.new( path => "~/Mail/INBOX/cur/uniquefilename:2,".IO );
#Create from maildir
my $file = IO::Maildir::File.new( dir => $maildir, name => "uniquefilename:2," );
=end code

Usually you don't need to do anything of the above, since you will receive your
C<IO::Maildir::File> objects from C<IO::Maildir>s methods.

=head3 attribute dir

=begin code
has IO::Maildir $.dir
=end code

Points to the maildir containing this file.

=head3 attribute name

=begin code
has $.name
=end code

Complete file name including flags and stuff.

=head3 method IO

=begin code
method IO( --> IO ) { ... }
=end code

Returns the C<IO::Path> object pointing to the file.

=head3 method flags

=begin code
method flags( --> Set ) { ... }
=end code

Returns the C<Set> of flags set for this file.

=head3 method flag

=begin code
multi method flag(:$agent = $maildir-agent, *%flags)
multi method flag(
	%flags where *.keys.Set ⊆ <P R S T D>.Set,
	:$agent = $maildir-agent)
=end code

Use this to set flags. Fails if C<$agent> is set to C<IO::Maildir::DELIVERY>.
This will also move the file to cur, because it has been seen by the MUA.

=head3 method move

=begin code
multi method move(IO::Maildir $maildir, Agent :$agent = $maildir-agent --> IO::Maildir::File) { ... }
multi method move (IO $iodir, Agent :$agent = $maildir-agent --> IO::Maildir::File) { ... }
=end code

Moves the file to a different maildir and returns the updated file-handle.
If called in C<IO::Maildir::DELIVERY> mode, the file will be moved to new and old
flags will be removed. If called in C<IO::Maildir::USER> mode, it will be moved to
cur and flags will be preserved.

=head1 AUTHOR

neula <thomas@famsim.de>

Source can be located at: L<https://github.com/neula/IO-Maildir> .
Comments and Pull Requests are welcome.

=head1 LICENSE

This library is free software; you may redistribute or modify it under the Artistic License 2.0.

=end pod
