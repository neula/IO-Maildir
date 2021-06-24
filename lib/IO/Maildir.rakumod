enum Agent ( DELIVERY => 'new', USER => 'cur' );

#weird stuff some MDAs set for example S=<filesize>
my regex baseflags { [\,<:Lu>\=\d+]* }
my regex mailflags { \:2 [\,|(P|R|S|T|D|F)|(<:Ll>)]* $ }

my $deliveries = 0;
my $msgdirs = <cur new tmp>;

multi is-maildir(IO $path --> Bool ) is export {
	?($path ~~ :d && $path.dir.grep( *.basename ∈ $msgdirs) == $msgdirs);
}

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

class IO::Maildir { ... };

class IO::Maildir::File does IO {
	has IO::Maildir $.dir;
	has $.name;

	method IO( --> IO ) { $!dir.IO.add($!name); }
	method flags( --> Set ) { set $/[*;*]».Str if ~$!name ~~ &mailflags }
	method flag(*%flags where *.keys.Set ⊆ <P R S T D>.Set ) {
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
		rename .add($!name), .add($uniq) given $!dir.IO;
		$!name = $uniq;
	}
	submethod TWEAK(IO :$path) {
		($!dir, $!name) = (maildir(.dirname), .basename) with $path;
	}
}

class IO::Maildir does IO {
	trusts IO::Maildir::File;

	has $.path handles <IO d e f l r rw rwx s w x z>;
	has Agent $.agent is rw = DELIVERY;

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
						 :$agent = $!agent --> IO::Path)
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
}

multi maildir($path) is export { IO::Maildir.new( $path.IO ) }