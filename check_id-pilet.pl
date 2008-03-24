#!/usr/bin/perl
use Getopt::Long;
use LWP;
use HTML::TreeBuilder;
use Nagios::Plugin;

my $PROGNAME = 'check_id-pilet';
our $VERSION = '0.9';

our $p = Nagios::Plugin->new(
	usage => "Usage: %s [ -v|--verbose ] [-t <timeout>]
    [ -i|--id=<id> ]
	",

	version => $VERSION,
    blurb => 'This plugin checks for the validity of id.ee tickets.',

	plugin  => $PROGNAME,
	shortname => $PROGNAME,
	timeout => 15,
);

$p->add_arg(
    spec => 'id|w=i',

    help =>
qq{-i, --id=STRING
   Personal ID or Ticket ID},

	required => 1,
);

$p->getopts;

my $id = $p->opts->id;
my $ua = LWP::UserAgent->new();
$ua->agent($PROGNAME.'/'. $VERSION);
my $url = 'https://www.pilet.ee/pages.php/0402010201';

my $res = $ua->post($url, { id => $id });
unless ($res->is_success) {
	$p->nagios_exit(ERROR, $res->status_line);
}

my $root = new HTML::TreeBuilder;
$root->parse($res->content);

my $table = $root->look_down('_tag' => 'td', 'id' => 'contentCell');
my $t = $table->find('p') or $p->nagios_exit(ERROR, "Couldn't parse html");
$t = $t->as_text;

$p->nagios_exit(OK, "Ticket $id valid") if $t =~ /^Isikul isikukoodiga \Q$id\E on olemas hetkel kehtiv ID-pilet\.$/;
$p->nagios_exit(ERROR, "Ticket $id not valid") if $t =~ /^Isikul isikukoodiga \Q$id\E ei ole olemas hetkel kehtivat ID-piletit\.$/;
$p->nagios_exit(WARN, "No active tickets") if $t =~ /^ID-kaardi nr \Q$id\E omanikuga ei ole seotud ühtegi kehtivat ID-piletit\.$/;
$p->nagios_exit(UNKNOWN, "No specific ticket specified") if $t =~ /^ID-kaardi nr \Q$id\E omanikuga on seotud järgmised ID-piletid\.$/;
$p->nagios_exit(ERROR, "Invalid input") if $t =~ /^Vigane ID-kaardi number või isikukood\.$/;
$p->nagios_exit(UNKNOWN, "Unknown parse status: ".$t);
