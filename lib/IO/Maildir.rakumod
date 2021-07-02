unit class IO::Maildir;

enum Agent ( DELIVERY => 'new', USER => 'cur' );

#weird stuff some MDAs set for example S=<filesize>
my regex baseflags { [\,<:Lu>\=\d+]* }
my regex mailflags { \:2 [\,|(P|R|S|T|D|F)|(<:Ll>)]* $ }


my $deliveries = 0;
my $msgdirs = <cur new tmp>;

our $agent = DELIVERY;

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
    method flag(
	:$agent = $maildir-agent,
	*%flags where *.keys.Set ⊆ <P R S T D>.Set )
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
    multi method move(IO::Maildir $maildir, Agent :$agent = $maildir-agent) {
	fail Nil unless $maildir ~~ :is-maildir;
	given $maildir.rename-or-mv( $.IO, $agent ) {
	    .flag(%.flags) if $agent ~~ USER;
	    $_;
	}
    }
    multi method move (IO $iodir, Agent :$agent = $maildir-agent) {
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
method create() {
    $msgdirs.map( { mkdir( $!path.add: $_ ) } );
}
multi method receive(IO $mail --> IO::Maildir::File) {
    fail Nil unless self ~~ :is-maildir;
    IO::Maildir::File.new(
	path => self!rename-or-mv($mail, agent => DELIVERY));
}
multi method receive(Str $mail --> IO::Maildir::File) {
    fail Nil unless self ~~ :is-maildir;
    my $mail-path = $!path.add("tmp/" ~ uniq());
    $mail-path.spurt($mail, :createonly);
    IO::Maildir::File.new(
	path => self!rename-or-mv($mail-path,
				  uniq => $mail-path.basename,
				  agent => DELIVERY));
}
method !rename-or-mv(IO $path,
		     Str :$uniq is copy = uniq(),
		     :$agent = $maildir-agent --> IO::Path)
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
    &padd-uniq.();
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

multi maildir($path) is export { IO::Maildir.new( $path.IO ) }
