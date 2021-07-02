use Test;
use IO::Maildir;

chdir("t".IO);
plan 12;

my $tdir = maildir "./testdir";
my $tstring = "HeyHeyMyMy\n";
my $mailfile;

$tdir.create;
ok ($tdir.path.add("new") ~~ :d), "Can create maildir directories";

isa-ok $mailfile = $tdir.receive($tstring), IO::Maildir::File, "Receiving a string...";
is $mailfile.IO.slurp, $tstring, ~$mailfile.name ~ " was written correctly.";
is ~$tdir.IO.add("new/" ~ ~$mailfile.name), $mailfile.IO, ~$mailfile.name ~ " ended up in the right place";

isa-ok $mailfile = $tdir.receive($mailfile.IO), IO::Maildir::File, "Receiving a file..";
is ~$tdir.IO.add("new/" ~ ~$mailfile.name), $mailfile.IO, ~$mailfile.name ~ " ended up in the right place";
cmp-ok $mailfile, 'eqv', $tdir.walk(agent => IO::Maildir::DELIVERY)[0], "File gets listed using walk";

fails-like { $mailfile.flag( D => True ) }, Exception, "Failing to set flags as DELIVERY agent (default)";
isa-ok $mailfile.flag(agent => IO::Maildir::USER, D => True ), Str, "Can set flags as USER agent";
is ~$tdir.IO.add("cur/" ~ ~$mailfile.name), $mailfile.IO, ~$mailfile.name ~ "Ended up in the right place (again)";
ok ($mailfile.flags ≡ set <D>), "Reading flags";

my $other-dir = maildir("./other-dir").create;
is ~$mailfile.move( $other-dir, agent => IO::Maildir::USER).IO, ~$other-dir.IO.add("cur/" ~ ~$mailfile.name), "moving works as well";

done-testing;
